@tool
class_name RegionAwareCondition
extends Condition

## A Condition with an optional spatial scope: a CollisionShape3D already present in the
## scenario scene tree bounds which entities the check considers. Subclasses (e.g.
## ConditionUnitCount) call region_contains() while filtering.
##
## A Condition is a Resource, so it CANNOT resolve a NodePath itself — a Resource has no
## position in the tree and no get_node(). Therefore the condition stores only the PATH; the
## owning GlobalTrigger (a Node, which does have tree context) resolves it against itself and
## injects the live node via bind_region() at arm() time. This keeps a serialized Node
## reference out of the resource (which wouldn't survive saving) while still letting you point
## a condition at an existing CollisionShape3D by dragging/typing a relative path.

#region Properties
## Path to a CollisionShape3D, authored RELATIVE TO THE OWNING GlobalTrigger node (e.g.
## "../ZoneA/CollisionShape3D"). Empty = no spatial scope; the whole map counts.
@export var region_shape_path: NodePath

## The resolved shape node, injected by the owning trigger at arm(). Never serialized; null
## when region_shape_path is empty or fails to resolve.
var _region: CollisionShape3D = null
#endregion


#region Region binding (called by the owning GlobalTrigger)
## Inject the resolved region node (or null). The trigger calls this during arm() after
## resolving region_shape_path against itself.
func bind_region(a_shape: CollisionShape3D) -> void:
	_region = a_shape


## Whether a live region is currently bound.
func has_region() -> bool:
	return _region != null and is_instance_valid(_region)


## Whether this check is meaningless without a region. False (the default) means the region
## is an optional narrowing — ConditionUnitCount with no region counts across the whole map,
## which is a legitimate thing to author. Subclasses whose entire purpose IS the region
## (ConditionUnitsInRegion) override this to true so the owning trigger can warn instead of
## silently matching everywhere.
func _region_is_required() -> bool:
	return false


## Called by the owning GlobalTrigger after bind_region(), to complain about a region that
## was asked for but isn't there. Both cases below are silent failures that read as "the
## trigger just never fires" or "the trigger fires immediately", which is a miserable thing
## to debug from the symptom.
func warn_about_missing_region(a_owner_name: String) -> void:
	if has_region():
		return
	if not region_shape_path.is_empty():
		push_warning(
			(
				(
					"%s: region_shape_path '%s' did not resolve to a CollisionShape3D. The check will "
					% [a_owner_name, region_shape_path]
				)
				+ "match ANYWHERE on the map. Paths are relative to the trigger node."
			)
		)
	elif _region_is_required():
		push_warning(
			(
				(
					"%s: %s needs a region but region_shape_path is empty, so it will match ANYWHERE "
					% [a_owner_name, _class_label()]
				)
				+ "on the map. Add a CollisionShape3D child and point the path at it."
			)
		)


## This condition's script class name, for warning text.
func _class_label() -> String:
	var script: Script = get_script()
	return String(script.get_global_name()) if script != null else "condition"


#endregion


#region Containment
## True if the world position falls within the bound region. With no region bound, there is
## no spatial restriction, so everything counts and this returns true. The test is a vertical
## prism — the shape's XZ footprint extruded through all heights — so units on uneven terrain
## aren't excluded by their Y. Handles Box / Sphere / Cylinder / Capsule; other shapes fall
## back to their axis-aligned XZ bounds.
func region_contains(a_world_pos: Vector3) -> bool:
	if not has_region():
		return true
	var shape: Shape3D = _region.shape
	if shape == null:
		return false
	# Work in the shape's own local space so translation, Y-rotation and scale are handled
	# uniformly; then drop to the shape-local XZ plane.
	var local: Vector3 = _region.global_transform.affine_inverse() * a_world_pos
	var lxz: Vector2 = Vector2(local.x, local.z)
	if shape is BoxShape3D:
		var half: Vector3 = (shape as BoxShape3D).size * 0.5
		return absf(lxz.x) <= half.x and absf(lxz.y) <= half.z
	if shape is SphereShape3D:
		return lxz.length() <= (shape as SphereShape3D).radius
	if shape is CylinderShape3D:
		return lxz.length() <= (shape as CylinderShape3D).radius
	if shape is CapsuleShape3D:
		return lxz.length() <= (shape as CapsuleShape3D).radius
	# Fallback: axis-aligned bounds of whatever shape this is.
	var aabb: AABB = shape.get_debug_mesh().get_aabb()
	return absf(lxz.x) <= aabb.size.x * 0.5 and absf(lxz.y) <= aabb.size.z * 0.5


#endregion


#region Player-facing description (highlights)
## The bound region's footprint — the same XZ prism region_contains() tests, so what the
## player sees painted is exactly what the check measures. Nothing when no region is bound
## (an unscoped condition covers the whole map, which isn't a useful thing to outline).
func highlight_shapes(_a_manager: ScenarioTriggerManager) -> Array[HighlightShape]:
	var result: Array[HighlightShape] = []
	if not has_region():
		return result
	# Built through a typed local rather than returned as an array literal: a literal is
	# untyped at runtime regardless of the declared return type, so callers assigning into an
	# Array[HighlightShape] would fail on it.
	var shape: HighlightShape = HighlightShape.from_collision_shape(_region)
	if shape != null:
		result.append(shape)
	return result
#endregion
