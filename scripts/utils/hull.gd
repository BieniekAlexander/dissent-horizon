class_name Hull
extends RefCounted

## A piece's footprint on the XZ plane: a circle or a rectangle rotated about Y. It is what
## every piece-to-piece range is measured between — reach, aggro, the leash, detection,
## interaction reach — so that "within R" means the same thing from both ends: the GAP
## between the two footprints is at most R. Why: gdd/systems/combat/range-buckets.md
## §Ranges are measured between hulls.
##
## Pure geometry on Vector2 values, so it is tested without an engine running. Height plays
## no part: every range volume is far taller than the world, and which LAYER (ground or air)
## a target sits on is decided by its targetable layers, not by altitude.

var center: Vector2
## Circle radius; 0.0 for a rectangle.
var radius: float = 0.0
## Half-size along the rectangle's own axes; ZERO for a circle.
var half_extents: Vector2 = Vector2.ZERO
## The rectangle's local X and Z axes, as unit vectors in world XZ.
var axis_x: Vector2 = Vector2.RIGHT
var axis_z: Vector2 = Vector2.DOWN


static func circle(at: Vector2, circle_radius: float) -> Hull:
	var hull := Hull.new()
	hull.center = at
	hull.radius = maxf(0.0, circle_radius)
	return hull


## A point is a circle of no size: what a region's centre, or a patch of ground, is measured
## as.
static func point(at: Vector2) -> Hull:
	return circle(at, 0.0)


static func rect(at: Vector2, half_size: Vector2, x_axis: Vector2, z_axis: Vector2) -> Hull:
	var hull := Hull.new()
	hull.center = at
	hull.half_extents = half_size.abs()
	hull.axis_x = x_axis.normalized()
	hull.axis_z = z_axis.normalized()
	return hull


func is_rect() -> bool:
	return half_extents != Vector2.ZERO


## The farthest this footprint reaches from its centre: the radius of the smallest circle
## about the centre that contains it. What a broad-phase query is grown by.
func extent() -> float:
	return half_extents.length() if is_rect() else radius


## Distance from this footprint's edge to `p`, or 0.0 when `p` lies inside it.
func distance_to_point(p: Vector2) -> float:
	if not is_rect():
		return maxf(0.0, center.distance_to(p) - radius)
	var offset: Vector2 = p - center
	var local := Vector2(absf(offset.dot(axis_x)), absf(offset.dot(axis_z)))
	return (local - half_extents).max(Vector2.ZERO).length()


## The four corners of a rectangle, or the empty list for a circle.
func corners() -> Array[Vector2]:
	if not is_rect():
		return []
	var ex: Vector2 = axis_x * half_extents.x
	var ez: Vector2 = axis_z * half_extents.y
	return [center + ex + ez, center + ex - ez, center - ex - ez, center - ex + ez]


## The gap between two footprints, or 0.0 when they touch or overlap. Symmetric:
## gap(a, b) == gap(b, a).
static func gap(a: Hull, b: Hull) -> float:
	if not a.is_rect():
		return maxf(0.0, b.distance_to_point(a.center) - a.radius)
	if not b.is_rect():
		return maxf(0.0, a.distance_to_point(b.center) - b.radius)
	if _rects_overlap(a, b):
		return 0.0
	# Two disjoint convex polygons are closest between a vertex of one and an edge of the
	# other, so the nearest corner-to-rectangle distance, taken both ways, is the gap.
	var best: float = INF
	for corner: Vector2 in a.corners():
		best = minf(best, b.distance_to_point(corner))
	for corner: Vector2 in b.corners():
		best = minf(best, a.distance_to_point(corner))
	return best


## Separating-axis test for two rectangles: they overlap unless one of their four edge
## directions separates their projections.
static func _rects_overlap(a: Hull, b: Hull) -> bool:
	for axis: Vector2 in [a.axis_x, a.axis_z, b.axis_x, b.axis_z]:
		if _projected_gap(a, b, axis) > 0.0:
			return false
	return true


static func _projected_gap(a: Hull, b: Hull, axis: Vector2) -> float:
	var spread: float = absf((b.center - a.center).dot(axis))
	return spread - _projected_half(a, axis) - _projected_half(b, axis)


static func _projected_half(hull: Hull, axis: Vector2) -> float:
	return hull.half_extents.x * absf(hull.axis_x.dot(axis)) \
		+ hull.half_extents.y * absf(hull.axis_z.dot(axis))
