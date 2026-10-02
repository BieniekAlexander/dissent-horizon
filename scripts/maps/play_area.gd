@tool
class_name PlayArea
extends RefCounted

## The rectangle of world the game is actually played on, as a centre, two perpendicular unit
## axes, and half-extents along them.
##
## A rectangle rather than a Rect2 because the play area is usually NOT axis-aligned with the
## world: TerrainData authors it in screen-aligned (s, t) coordinates, which is a rectangle
## rotated 45° in world XZ (see TerrainData.play_size — "the two axes are independent"). A
## Rect2 could only hold its bounding box, which is bigger than the play area by exactly the
## four dead corners a consumer is usually trying to exclude.
##
## Carrying the axes makes the frame explicit, so a consumer clamps or measures ALONG the play
## area's own axes instead of guessing. to_local / to_world are the whole interface: work in
## local coordinates, where the rectangle is just ±half.

#region Constants
const INV_SQRT2: float = 0.7071067811865476
#endregion

#region Properties
## World-XZ centre.
var center: Vector2 = Vector2.ZERO
## Perpendicular unit axes in world XZ. `half.x` is measured along `axis_a`, `half.y` along
## `axis_b`.
var axis_a: Vector2 = Vector2.RIGHT
var axis_b: Vector2 = Vector2.DOWN
## Half-extents along the axes, in world units.
var half: Vector2 = Vector2.ZERO
#endregion


#region Constructors
## A rectangle aligned with the world X/Z axes — the shape of a raw heightmap, and the
## fallback for a map that declares no play bounds.
static func axis_aligned(center: Vector2, half: Vector2) -> PlayArea:
	var area := PlayArea.new()
	area.center = center
	area.axis_a = Vector2.RIGHT
	area.axis_b = Vector2.DOWN
	area.half = half
	return area


## A rectangle in the screen-aligned frame TerrainData authors play bounds in: s = x+z runs
## into the screen, t = x−z runs across it.
##
## `half_st` is in (s, t) units as TerrainData reports them; one unit of s covers 1/√2 of world
## distance along the s direction, hence the conversion. `cell_size` scales grid units to
## world units.
static func screen_aligned(center: Vector2, half_st: Vector2, cell_size: float) -> PlayArea:
	var area := PlayArea.new()
	area.center = center
	area.axis_a = Vector2(INV_SQRT2, INV_SQRT2)  # s = x + z
	area.axis_b = Vector2(INV_SQRT2, -INV_SQRT2)  # t = x - z
	area.half = half_st * cell_size * INV_SQRT2
	return area


#endregion


#region Public API
## Whether this rectangle encloses anything. A degenerate one means "no bounds to enforce".
func is_valid() -> bool:
	return half.x > 0.0 and half.y > 0.0


## A world point in the rectangle's own frame, where the rectangle is exactly ±half.
func to_local(a_world: Vector2) -> Vector2:
	var offset: Vector2 = a_world - center
	return Vector2(offset.dot(axis_a), offset.dot(axis_b))


## The inverse of to_local. Exact, because the axes are orthonormal.
func to_world(a_local: Vector2) -> Vector2:
	return center + axis_a * a_local.x + axis_b * a_local.y


## A world DIRECTION in the rectangle's own frame — to_local without the translation, for
## vectors that describe a heading rather than a place (e.g. which way the camera looks).
## Rotating a direction through to_local would offset it by the centre and point it wrongly.
func to_local_direction(a_world_dir: Vector2) -> Vector2:
	return Vector2(a_world_dir.dot(axis_a), a_world_dir.dot(axis_b))


#endregion


#region Leaving the play area
## The point on this rectangle's PERIMETER closest to `world`.
##
## Defined for a point INSIDE the rectangle as well as outside — an interior point is
## pushed out to whichever of the four edges it is nearest. That is what makes it answer
## "which way is off the map from here" for a caster standing anywhere on the board, which
## is the only reason this function exists (see OffMapArrival).
func nearest_perimeter_point(a_world: Vector2) -> Vector2:
	var local: Vector2 = to_local(a_world)
	var edge := Vector2(clampf(local.x, -half.x, half.x), clampf(local.y, -half.y, half.y))
	if not edge.is_equal_approx(local):
		# Outside already: the clamp IS the nearest boundary point.
		return to_world(edge)
	# Inside: leave by whichever edge has the least clearance left.
	if half.x - absf(local.x) <= half.y - absf(local.y):
		edge.x = _extent_toward(local.x, half.x)
	else:
		edge.y = _extent_toward(local.y, half.y)
	return to_world(edge)


## A point `margin` world-units OUTSIDE the rectangle, on the ray running from `world`
## through its nearest perimeter point — where something arriving from beyond the play
## space starts.
##
## A `world` that is ITSELF on the perimeter leaves no ray to follow, so the edge's own
## outward normal stands in. Not a corner case to shrug at: a caster parked against the
## map edge is exactly where a player puts a building.
func exterior_point(a_world: Vector2, a_margin: float) -> Vector2:
	var edge: Vector2 = nearest_perimeter_point(a_world)
	var outward: Vector2 = edge - a_world
	if outward.is_zero_approx():
		outward = _outward_normal_at(edge)
	return edge + outward.normalized() * a_margin


## Whether `world` lies more than `margin` beyond the rectangle on either of its own axes
## — the test for "it has left the map", and the mirror of exterior_point's arrival.
func is_beyond(a_world: Vector2, a_margin: float) -> bool:
	var local: Vector2 = to_local(a_world)
	return absf(local.x) > half.x + a_margin or absf(local.y) > half.y + a_margin


## The longest straight line that fits across the rectangle. Nothing crossing the play area
## can need to travel further than this to leave it, which is what a fly-through
## destination is sized from rather than solving for the actual boundary crossing.
func diagonal() -> float:
	return half.length() * 2.0


#endregion


#region Private helpers
## The half-extent `coordinate` points toward, signed. Zero counts as the positive side —
## arbitrary but consistent, for a point exactly on a mid-line that is equidistant from
## both edges.
static func _extent_toward(coordinate: float, extent: float) -> float:
	return extent if coordinate >= 0.0 else -extent


## Outward unit normal, in world XZ, of the edge `edge` lies on. Only reached from
## exterior_point's degenerate ray, so a point that is not actually on the perimeter simply
## gets the normal of the edge it is closest to.
func _outward_normal_at(a_edge: Vector2) -> Vector2:
	var local: Vector2 = to_local(a_edge)
	if absf(absf(local.x) - half.x) <= absf(absf(local.y) - half.y):
		return axis_a * signf(_extent_toward(local.x, half.x))
	return axis_b * signf(_extent_toward(local.y, half.y))
#endregion
