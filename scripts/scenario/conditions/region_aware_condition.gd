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
func bind_region(shape: CollisionShape3D) -> void:
	_region = shape


## Whether a live region is currently bound.
func has_region() -> bool:
	return _region != null and is_instance_valid(_region)
#endregion

#region Containment
## True if the world position falls within the bound region. With no region bound, there is
## no spatial restriction, so everything counts and this returns true. The test is a vertical
## prism — the shape's XZ footprint extruded through all heights — so units on uneven terrain
## aren't excluded by their Y. Handles Box / Sphere / Cylinder / Capsule; other shapes fall
## back to their axis-aligned XZ bounds.
func region_contains(world_pos: Vector3) -> bool:
	if not has_region():
		return true
	var shape: Shape3D = _region.shape
	if shape == null:
		return false
	# Work in the shape's own local space so translation, Y-rotation and scale are handled
	# uniformly; then drop to the shape-local XZ plane.
	var local: Vector3 = _region.global_transform.affine_inverse() * world_pos
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
