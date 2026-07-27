class_name HighlightShape
extends RefCounted

## A flat, ground-plane footprint that a ScenarioHighlight paints for the player: "this is
## the place the objective is talking about."
##
## It exists so a Condition can describe its spatial scope WITHOUT knowing anything about
## rendering, and without the painter having to re-derive that scope from whatever the
## condition happened to store. Conditions express their region three different ways — a
## bound CollisionShape3D (RegionAwareCondition), inline rect/circle exports
## (ConditionUnitsInRegion), a grid cell (ConditionStructureBuilt) — and every one of them
## collapses to a rotated rectangle or a circle on the XZ plane. That's the whole type.
##
## Everything is world-space XZ; Y is supplied by the terrain at paint time, so a footprint
## drapes over hills instead of hovering on a flat plane (the same reason
## RegionAwareCondition.region_contains treats regions as vertical prisms).

#region Constants
enum Kind { CIRCLE, RECT }
#endregion

#region Properties
var kind: Kind = Kind.CIRCLE
## World-space XZ centre.
var center: Vector2 = Vector2.ZERO
## CIRCLE only.
var radius: float = 1.0
## RECT only: half-width along the rect's own local X / Z axes.
var half_extents: Vector2 = Vector2.ONE
## RECT only: yaw of the rect's local axes, radians.
var rotation_y: float = 0.0
#endregion

#region Constructors
static func circle(center: Vector2, radius: float) -> HighlightShape:
	var s := HighlightShape.new()
	s.kind = Kind.CIRCLE
	s.center = center
	s.radius = maxf(radius, 0.01)
	return s


static func rect(center: Vector2, half_extents: Vector2, rotation_y: float = 0.0) -> HighlightShape:
	var s := HighlightShape.new()
	s.kind = Kind.RECT
	s.center = center
	s.half_extents = Vector2(maxf(half_extents.x, 0.01), maxf(half_extents.y, 0.01))
	s.rotation_y = rotation_y
	return s


## The XZ footprint of a live CollisionShape3D, in world space — the counterpart of
## RegionAwareCondition.region_contains, which tests the same footprint. Returns null for a
## shapeless / freed node so callers can just skip it.
##
## Scale is taken from the node's global basis so a scaled region marker paints at the size
## it actually tests at; rotation is read as yaw only, matching the containment test's
## assumption that regions are authored upright.
static func from_collision_shape(node: CollisionShape3D) -> HighlightShape:
	if node == null or not is_instance_valid(node) or node.shape == null:
		return null
	var xform: Transform3D = node.global_transform
	var center_xz: Vector2 = Vector2(xform.origin.x, xform.origin.z)
	var scale: Vector3 = xform.basis.get_scale()
	var yaw: float = xform.basis.get_euler().y
	var shape: Shape3D = node.shape
	if shape is BoxShape3D:
		var half: Vector3 = (shape as BoxShape3D).size * 0.5
		return HighlightShape.rect(
			center_xz, Vector2(half.x * scale.x, half.z * scale.z), yaw
		)
	# Sphere / Cylinder / Capsule all reduce to a disc on XZ. Non-uniform scale would make
	# that an ellipse; use the larger axis so the paint never under-states the region.
	var planar_scale: float = maxf(absf(scale.x), absf(scale.z))
	if shape is SphereShape3D:
		return HighlightShape.circle(center_xz, (shape as SphereShape3D).radius * planar_scale)
	if shape is CylinderShape3D:
		return HighlightShape.circle(center_xz, (shape as CylinderShape3D).radius * planar_scale)
	if shape is CapsuleShape3D:
		return HighlightShape.circle(center_xz, (shape as CapsuleShape3D).radius * planar_scale)
	# Same fallback region_contains uses: the shape's axis-aligned XZ bounds.
	var aabb: AABB = shape.get_debug_mesh().get_aabb()
	return HighlightShape.rect(
		center_xz, Vector2(aabb.size.x * 0.5 * scale.x, aabb.size.z * 0.5 * scale.z), yaw
	)
#endregion

#region Geometry
## The footprint's outline as world-space XZ points, closed implicitly (the caller loops
## back to point 0). `segments` is the circle tessellation; rectangles ignore it.
func outline(a_segments: int = 32) -> Array[Vector2]:
	var points: Array[Vector2] = []
	if kind == Kind.RECT:
		var corners: Array[Vector2] = [
			Vector2(-half_extents.x, -half_extents.y),
			Vector2(half_extents.x, -half_extents.y),
			Vector2(half_extents.x, half_extents.y),
			Vector2(-half_extents.x, half_extents.y),
		]
		for corner: Vector2 in corners:
			points.append(center + _local_to_world_xz(corner))
		return points
	for i: int in a_segments:
		var angle: float = TAU * float(i) / float(a_segments)
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return points


## The outline subdivided so no edge spans more than `spacing` world units.
##
## Both consumers need this and for the same reason — four stretched corner points are not a
## rectangle once anything is sampled along them. The world painter drapes each point onto
## the terrain (a long edge would otherwise cut straight through a hill); the minimap turns
## each into a pixel (a long edge would otherwise be four dots).
func perimeter_points(a_spacing: float) -> Array[Vector2]:
	var corners: Array[Vector2] = outline()
	var sampled: Array[Vector2] = []
	var step: float = maxf(a_spacing, 0.01)
	for i: int in corners.size():
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % corners.size()]
		sampled.append(a)
		var steps: int = int(a.distance_to(b) / step)
		for s: int in range(1, steps):
			sampled.append(a.lerp(b, float(s) / float(steps)))
	return sampled


## Rotate a shape-local (x, z) offset into world XZ. NOT Vector2.rotated(rotation_y):
## `rotation_y` is a 3D yaw, i.e. Basis(Vector3.UP, rotation_y), whose X axis is
## (cos, 0, -sin). Mapping that onto a Vector2 whose y component IS z flips the sense of
## the rotation, so a rect authored at +30° would paint mirrored about its own axis.
func _local_to_world_xz(a_local: Vector2) -> Vector2:
	var c: float = cos(rotation_y)
	var s: float = sin(rotation_y)
	return Vector2(a_local.x * c + a_local.y * s, -a_local.x * s + a_local.y * c)
#endregion
