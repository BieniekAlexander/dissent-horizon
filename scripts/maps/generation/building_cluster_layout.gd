@tool
class_name BuildingClusterLayout
extends RefCounted

## Lays out one neutral building cluster (map-generation.md §Building layout). A cluster is a
## set of GROUPINGS: one to `grouping_size_weights.size()` buildings standing a tight gap apart
## with flush edges, like a row of houses. Groupings stand an OPEN gap from each other — never
## narrower — and each within the open gap's maximum of one already placed, so the cluster
## stays one landmark.
##
## Every gap is the CHEBYSHEV gap between footprints: the clear cells between them along the
## axis they are furthest apart on. It is what a square-eroded navmesh lets through, so a tight
## gap passes only small units and an open one passes every size class.
##
## Pure and static over a caller-owned generator and a free-footprint test.

## A side of a footprint, by the axis it faces along and which end.
enum Side { LOW_X, HIGH_X, LOW_Z, HIGH_Z }

#region Constants
## Draws for one building's place in its grouping before the grouping's shape is redrawn.
const MEMBER_DRAWS: int = 16
## Shapes drawn for one grouping before the cluster candidate is abandoned.
const SHAPE_DRAWS: int = 8
## Draws for one grouping's place in the cluster before the cluster candidate is abandoned.
const GROUPING_DRAWS: int = 48
#endregion


## Origins for `pieces` grown from `seed_cell`, as placements in MapFeature.placements' shape
## (turned to lie parallel within a grouping); empty when the draws run out. `is_rect_free` is
## (origin: Vector2i, dims: Vector2i) -> bool.
##
## `fixed` footprints already stand and count as the cluster's first grouping — a shelter the
## cluster is built around — so every grouping keeps the open gap from them, the cluster grows
## from them rather than from `seed_cell`, and they are not among the placements returned.
static func lay_out(
	rng: RandomNumberGenerator,
	pieces: Array[MapPiece],
	seed_cell: Vector2i,
	is_rect_free: Callable,
	params: MapGenerationParams,
	fixed: Array[Rect2i] = []
) -> Array[Dictionary]:
	var placed: Array[Rect2i] = []
	placed.assign(fixed)
	var placements: Array[Dictionary] = []
	for drawn: Array in partition(rng, pieces, params.grouping_size_weights):
		var grouping: Array[MapPiece] = []
		grouping.assign(drawn)
		var laid: Dictionary = _place_grouping(
			rng, grouping, seed_cell, placed, is_rect_free, params
		)
		if laid.is_empty():
			return []
		var rects: Array[Rect2i] = laid.rects
		for i: int in grouping.size():
			placements.append(
				{
					piece = grouping[i],
					origin = rects[i].position,
					quarter_turns = (laid.turns as Array[int])[i],
				}
			)
		placed.append_array(rects)
	return placements


## Cut `pieces`, in order, into groupings whose sizes are drawn by `size_weights` (index i
## weighs size i + 1), the last cut short by what is left.
static func partition(
	rng: RandomNumberGenerator, pieces: Array[MapPiece], size_weights: PackedFloat32Array
) -> Array[Array]:
	var groupings: Array[Array] = []
	var next: int = 0
	while next < pieces.size():
		var size: int = maxi(GenerationRandom.weighted_index(rng, size_weights) + 1, 1)
		var grouping: Array[MapPiece] = pieces.slice(next, mini(next + size, pieces.size()))
		groupings.append(grouping)
		next += grouping.size()
	return groupings


## Clear cells between two footprints along the axis they are furthest apart on: negative when
## they overlap, 0 when they touch at an edge or a corner.
static func chebyshev_gap(a: Rect2i, b: Rect2i) -> int:
	return maxi(
		_axis_gap(a.position.x, a.end.x, b.position.x, b.end.x),
		_axis_gap(a.position.y, a.end.y, b.position.y, b.end.y)
	)


## Whether two footprints face each other across one axis with one pair of their side edges in
## line — a row of houses, not a stagger.
static func is_flush(a: Rect2i, b: Rect2i) -> bool:
	var apart_x: bool = _axis_gap(a.position.x, a.end.x, b.position.x, b.end.x) >= 0
	var apart_z: bool = _axis_gap(a.position.y, a.end.y, b.position.y, b.end.y) >= 0
	if apart_x == apart_z:
		return false
	if apart_x:
		return a.position.y == b.position.y or a.end.y == b.end.y
	return a.position.x == b.position.x or a.end.x == b.end.x


static func _axis_gap(a_low: int, a_high: int, b_low: int, b_high: int) -> int:
	return maxi(b_low - a_high, a_low - b_high)


#region Groupings
## One grouping placed, as {rects: Array[Rect2i], turns: Array[int]} per member: centred on
## `seed_cell` when it is the first, otherwise an open gap from a building already placed. Empty
## when no shape or position worked.
static func _place_grouping(
	rng: RandomNumberGenerator,
	grouping: Array[MapPiece],
	seed_cell: Vector2i,
	placed: Array[Rect2i],
	is_rect_free: Callable,
	params: MapGenerationParams
) -> Dictionary:
	for _shape: int in SHAPE_DRAWS:
		var turns: Array[int] = grouping_turns(grouping, rng.randf() < 0.5)
		var dims: Array[Vector2i] = []
		for i: int in grouping.size():
			dims.append(Fixture.oriented_dimensions(grouping[i].footprint, turns[i]))
		var shape: Array[Rect2i] = _grouping_shape(rng, dims, params)
		if shape.is_empty():
			continue
		if placed.is_empty():
			var bounds: Rect2i = _bounds(shape)
			var rects: Array[Rect2i] = _shifted(shape, seed_cell - bounds.get_center())
			if _all_free(rects, is_rect_free):
				return {rects = rects, turns = turns}
			continue
		for _draw: int in GROUPING_DRAWS:
			var rects: Array[Rect2i] = _beside(rng, shape, placed, params)
			if rects.is_empty():
				continue
			if _keeps_open_gap(rects, placed, params) and _all_free(rects, is_rect_free):
				return {rects = rects, turns = turns}
	return {}


## Quarter turns that lay every non-square piece of a grouping with its long side along x (or z,
## when `is_long_in_x` is false), so a grouping's long walls run parallel. A square piece is
## never turned.
static func grouping_turns(grouping: Array[MapPiece], is_long_in_x: bool) -> Array[int]:
	var turns: Array[int] = []
	for piece: MapPiece in grouping:
		var size: Vector2i = piece.footprint
		var is_already_aligned: bool = (
			size.x == size.y or (size.x > size.y) == is_long_in_x
		)
		turns.append(0 if is_already_aligned else 1)
	return turns


## A grouping's footprints in local cells, from its members' turned `dims`: the first at the
## origin, each next one a tight gap off a side of a random member, flush with it. Empty when a
## member found no room.
static func _grouping_shape(
	rng: RandomNumberGenerator, dims: Array[Vector2i], params: MapGenerationParams
) -> Array[Rect2i]:
	var rects: Array[Rect2i] = [Rect2i(Vector2i.ZERO, dims[0])]
	for i: int in range(1, dims.size()):
		var rect: Rect2i = _flush_member(rng, dims[i], rects, params)
		if rect.size == Vector2i.ZERO:
			return []
		rects.append(rect)
	return rects


static func _flush_member(
	rng: RandomNumberGenerator, dims: Vector2i, rects: Array[Rect2i], params: MapGenerationParams
) -> Rect2i:
	for _draw: int in MEMBER_DRAWS:
		var anchor: Rect2i = rects[rng.randi() % rects.size()]
		var gap: int = rng.randi_range(params.grouping_gap_cells_min, params.grouping_gap_cells_max)
		var side: Side = (rng.randi() % Side.size()) as Side
		var origin: Vector2i = _across(rng, anchor, dims, gap, side)
		# Flush: one of the two side edges in line with the anchor's.
		var is_stacked_in_z: bool = (
			origin.y >= anchor.end.y or origin.y + dims.y <= anchor.position.y
		)
		var is_to_low_edge: bool = rng.randf() < 0.5
		if is_stacked_in_z:
			origin.x = anchor.position.x if is_to_low_edge else anchor.end.x - dims.x
		else:
			origin.y = anchor.position.y if is_to_low_edge else anchor.end.y - dims.y
		var rect := Rect2i(origin, dims)
		if rects.all(func(other: Rect2i) -> bool: return chebyshev_gap(rect, other) >= 1):
			return rect
	return Rect2i()


## The grouping `shape` moved so a random member of it faces a random placed building across a
## random open gap, overlapping it along the facing side by at least one cell. The side is one
## that grows the cluster along its SHORTER axis, and a shape that would stretch the longer axis
## by more than `cluster_span_slack_cells` is refused: a cluster fills out toward square rather
## than trailing off in a line. Empty when the shape was refused.
static func _beside(
	rng: RandomNumberGenerator,
	shape: Array[Rect2i],
	placed: Array[Rect2i],
	params: MapGenerationParams
) -> Array[Rect2i]:
	var bounds: Rect2i = _bounds(placed)
	var sides: Array[int] = _growth_sides(bounds)
	var side: Side = sides[rng.randi() % sides.size()] as Side
	var anchor: Rect2i = placed[rng.randi() % placed.size()]
	var member: Rect2i = shape[rng.randi() % shape.size()]
	var gap: int = rng.randi_range(
		params.cluster_open_gap_cells_min, params.cluster_open_gap_cells_max
	)
	var rects: Array[Rect2i] = _shifted(
		shape, _across(rng, anchor, member.size, gap, side) - member.position
	)
	if sides.size() == Side.size():
		return rects
	var is_long_in_x: bool = side == Side.LOW_Z or side == Side.HIGH_Z
	var grown: Rect2i = bounds.merge(_bounds(rects))
	var span: int = bounds.size.x if is_long_in_x else bounds.size.y
	var new_span: int = grown.size.x if is_long_in_x else grown.size.y
	var own_span: int = _bounds(rects).size.x if is_long_in_x else _bounds(rects).size.y
	# A grouping longer than the cluster's span cannot fit inside it; it may overhang by its excess.
	var allowed: int = maxi(params.cluster_span_slack_cells, own_span - span)
	if new_span - span > allowed:
		rects.clear()
	return rects


## The sides a new grouping may stand on: across the shorter axis of the cluster's bounds, or any
## side once the two axes are the same length.
static func _growth_sides(bounds: Rect2i) -> Array[int]:
	if bounds.size.x > bounds.size.y:
		return [Side.LOW_Z, Side.HIGH_Z]
	if bounds.size.y > bounds.size.x:
		return [Side.LOW_X, Side.HIGH_X]
	return [Side.LOW_X, Side.HIGH_X, Side.LOW_Z, Side.HIGH_Z]


## An origin for a `dims` footprint `gap` cells off `side` of `anchor`, slid along that side
## anywhere it still overlaps the anchor by a cell.
static func _across(
	rng: RandomNumberGenerator, anchor: Rect2i, dims: Vector2i, gap: int, side: Side
) -> Vector2i:
	var slide_x: int = rng.randi_range(anchor.position.x - dims.x + 1, anchor.end.x - 1)
	var slide_z: int = rng.randi_range(anchor.position.y - dims.y + 1, anchor.end.y - 1)
	match side:
		Side.HIGH_X:
			return Vector2i(anchor.end.x + gap, slide_z)
		Side.LOW_X:
			return Vector2i(anchor.position.x - gap - dims.x, slide_z)
		Side.HIGH_Z:
			return Vector2i(slide_x, anchor.end.y + gap)
	return Vector2i(slide_x, anchor.position.y - gap - dims.y)


## Every new footprint at least the open minimum from every placed one, so no tight gap — and
## no gap between tight and open — joins two groupings.
static func _keeps_open_gap(
	rects: Array[Rect2i], placed: Array[Rect2i], params: MapGenerationParams
) -> bool:
	for rect: Rect2i in rects:
		for other: Rect2i in placed:
			if chebyshev_gap(rect, other) < params.cluster_open_gap_cells_min:
				return false
	return true


#endregion


#region Rect helpers
static func _all_free(rects: Array[Rect2i], is_rect_free: Callable) -> bool:
	return rects.all(func(rect: Rect2i) -> bool: return is_rect_free.call(rect.position, rect.size))


static func _shifted(rects: Array[Rect2i], by: Vector2i) -> Array[Rect2i]:
	var moved: Array[Rect2i] = []
	moved.assign(
		rects.map(func(rect: Rect2i) -> Rect2i: return Rect2i(rect.position + by, rect.size))
	)
	return moved


static func _bounds(rects: Array[Rect2i]) -> Rect2i:
	var bounds: Rect2i = rects[0]
	for rect: Rect2i in rects:
		bounds = bounds.merge(rect)
	return bounds
#endregion
