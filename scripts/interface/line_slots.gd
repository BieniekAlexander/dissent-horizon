class_name LineSlots
extends RefCounted

## The geometry of a MOVE-LINE order: where N actors stand along a line the player dragged, and
## which actor takes which spot. Pure and scene-tree-free, like StartingFormation, so the rule can
## be pinned without a controller. Why it works this way:
## gdd/systems/commands/move-line-drag.md.

## How much clear ground each actor is given, as a multiple of the largest actor's diameter. A
## little over 1.0 so bodies at the limit still have room to turn.
const SPACING_FACTOR: float = 1.1

## Below this the line is a point and has no direction of its own.
const MIN_LENGTH: float = 0.001


## The spacing between neighbours for actors of up to `a_radius`.
static func spacing_for_radius(a_radius: float) -> float:
	return maxf(a_radius, 0.01) * 2.0 * SPACING_FACTOR


## `a_count` standing points for a line from `a_start` to `a_end`.
##
## One actor takes the END of the line. Otherwise, when the line is long enough that everyone fits
## single file at `a_spacing` or better, they are spread at EQUAL intervals from end to end. When
## it is not, the actors form ROWS along it: as many per row as the line holds at `a_spacing`, the
## first row on the line and each next one a `a_spacing` further toward `a_back` (a unit vector,
## the side the actors are coming from). A short last row is spread across the line rather than
## bunched at one end.
static func slots(
	a_start: Vector2, a_end: Vector2, a_spacing: float, a_count: int, a_back: Vector2
) -> Array[Vector2]:
	var result: Array[Vector2] = []
	if a_count <= 0:
		return result
	if a_count == 1:
		result.append(a_end)
		return result

	var length: float = a_start.distance_to(a_end)
	var direction: Vector2 = axis(a_start, a_end)
	var back: Vector2 = a_back.normalized() if a_back.length() > MIN_LENGTH else -perpendicular(direction)
	var per_row: int = maxi(1, floori(length / maxf(a_spacing, 0.01)) + 1)
	if per_row >= a_count:
		per_row = a_count

	var placed: int = 0
	var row: int = 0
	while placed < a_count:
		var in_row: int = mini(per_row, a_count - placed)
		for i: int in in_row:
			var along: float = length * 0.5
			if in_row > 1:
				along = length * float(i) / float(in_row - 1)
			result.append(a_start + direction * along + back * a_spacing * float(row))
		placed += in_row
		row += 1
	return result


## Hand each actor a point. The actors are interchangeable, so this is NOT a best match: both
## sides are sorted along the line's axis and zipped, which is cheap, deterministic and keeps the
## paths from crossing for the usual case of a group that stands roughly in one place.
##
## Returns, for each actor index, the index of the slot it takes. Sizes must match.
static func assign(a_actors: Array[Vector2], a_slots: Array[Vector2], a_axis: Vector2) -> Array[int]:
	var count: int = mini(a_actors.size(), a_slots.size())
	var perp: Vector2 = perpendicular(a_axis)
	var actor_order: Array[int] = _sorted_indices(a_actors, a_axis, perp)
	var slot_order: Array[int] = _sorted_indices(a_slots, a_axis, perp)
	var result: Array[int] = []
	result.resize(a_actors.size())
	result.fill(-1)
	for i: int in count:
		result[actor_order[i]] = slot_order[i]
	return result


## The unit vector from `a_start` to `a_end`; RIGHT for a line with no length.
static func axis(a_start: Vector2, a_end: Vector2) -> Vector2:
	var delta: Vector2 = a_end - a_start
	if delta.length() < MIN_LENGTH:
		return Vector2.RIGHT
	return delta.normalized()


static func perpendicular(a_axis: Vector2) -> Vector2:
	return Vector2(-a_axis.y, a_axis.x)


## The unit perpendicular to the line that points toward `a_from`, so rows form on the side the
## actors came from.
static func back_toward(a_start: Vector2, a_end: Vector2, a_from: Vector2) -> Vector2:
	var perp: Vector2 = perpendicular(axis(a_start, a_end))
	return perp if (a_from - a_start).dot(perp) >= 0.0 else -perp


static func _sorted_indices(a_points: Array[Vector2], a_axis: Vector2, a_perp: Vector2) -> Array[int]:
	var indices: Array[int] = []
	for i: int in a_points.size():
		indices.append(i)
	# Index last in the comparison so equal keys still order the same way every time; sort_custom
	# is not stable.
	indices.sort_custom(
		func(a: int, b: int) -> bool:
			var ka: float = a_points[a].dot(a_axis)
			var kb: float = a_points[b].dot(a_axis)
			if not is_equal_approx(ka, kb):
				return ka < kb
			var pa: float = a_points[a].dot(a_perp)
			var pb: float = a_points[b].dot(a_perp)
			if not is_equal_approx(pa, pb):
				return pa < pb
			return a < b
	)
	return indices
