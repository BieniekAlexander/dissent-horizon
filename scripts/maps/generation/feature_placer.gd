@tool
class_name FeaturePlacer
extends RefCounted

## Places one planned feature at a time by BEST-CANDIDATE: draw a bounded number of valid
## positions, score each against the feature's target share (plus collocation), keep the best.
## The work is bounded by candidates x features, so placement cannot spin the way
## guess-and-check can (map-generation.md §3).
##
## Holds the placement state — the grid, the features so far — because each placement
## narrows the next; see PlacementGrid for why that state is kept rather than recomputed.

#region Constants
## A pond's pan is sunk exactly one slope step: its rim cells then spread exactly
## MAX_SLOPE_DIFF, which is walkable but not flat (map-composition.md §The basin).
const POND_SINK: float = TerrainGrid.MAX_SLOPE_DIFF
## Water level above the pan floor, as a fraction of the sink. A rim cell's mean height is at
## least a quarter-sink above the floor (three of its corners lowered at most), so any fraction
## below 0.25 floods the pan and nothing else.
const POND_LEVEL_FRACTION: float = 0.2
## Random jitter, in cells, on each frontier cell's distance while a pond grows — the
## irregularity of its outline. Zero grows a lozenge.
const POND_GROWTH_NOISE_CELLS: float = 2.5
## Rim cells kept clear around a pond: the ring whose corners the pan lowers.
const POND_RIM_CELLS: int = 1
## Draws per cluster member before the cluster candidate is abandoned.
const CLUSTER_MEMBER_DRAWS: int = 48
## Draws per extra site of a site cluster before the candidate is abandoned.
const SITE_ADJACENCY_DRAWS: int = 12

const _NEIGHBOURS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
]
#endregion

#region Properties
var _params: MapGenerationParams
var _rng: RandomNumberGenerator
var _grid: PlacementGrid
var _starts: Array[MapStart]
var _placed: Array[MapFeature] = []
## Kind -> every placed cluster's footprints of that kind, as Rect2i, for the separation test.
## Kept beside _placed because rebuilding it per candidate would rescan every placement.
var _cluster_rects: Dictionary = {}
## Kind pair (Vector2i(placing, placed)) -> CollocationRule.
var _rules: Dictionary = {}
## Where candidates are drawn: the whole grid, or pass 4's neighbourhood of a moved feature.
var _window := Rect2i()
## How a candidate's access share is measured: straight-line by default (pass 3), walking
## distance when pass 4 re-places a feature. (point: Vector2) -> PackedFloat32Array.
var _share_of: Callable
#endregion


func _init(
	a_params: MapGenerationParams,
	a_rng: RandomNumberGenerator,
	a_grid: PlacementGrid,
	a_starts: Array[MapStart]
) -> void:
	_params = a_params
	_rng = a_rng
	_grid = a_grid
	_starts = a_starts
	for rule: CollocationRule in a_params.collocation_rules:
		_rules[Vector2i(rule.placing, rule.placed)] = rule
	_window = Rect2i(0, 0, a_grid.width, a_grid.depth)
	_share_of = func(point: Vector2) -> PackedFloat32Array:
		return MapFavor.access_share(point, _starts, _params.alliance_count)


## Draw later candidates only within `a_radius` (L-infinity) of `a_center`, and score them by
## `a_share_of` — how pass 4 moves a feature near where it stood.
func restrict(a_center: Vector2, a_radius: float, a_share_of: Callable) -> void:
	var low := Vector2i((a_center - Vector2.ONE * a_radius).floor()).max(Vector2i.ZERO)
	var high := Vector2i((a_center + Vector2.ONE * a_radius).ceil()).min(
		Vector2i(_grid.width, _grid.depth)
	)
	_window = Rect2i(low, (high - low).max(Vector2i.ONE))
	_share_of = a_share_of


## Take features already on the map as placed, without re-placing them: they reserve their
## ground and count for spacing, separation and collocation.
func adopt(a_features: Array[MapFeature]) -> void:
	for feature: MapFeature in a_features:
		_commit(feature)


## Place `plan` as near `target` share as the candidate budget allows, and commit it. Null when
## no valid position was found at all.
##
## Collocation is weighted by `freedom` (see MapFavor.steer): a feature that later ones can no
## longer balance places for balance, and only features with slack behind them trade favor
## for company.
func place(a_plan: FeaturePlan, a_target: PackedFloat32Array, a_freedom: float = 1.0) -> MapFeature:
	var best: MapFeature = null
	var best_score: float = INF
	var found: int = 0
	var draws: int = _params.placement_candidates * _params.candidate_draw_factor
	for _i: int in draws:
		if found >= _params.placement_candidates:
			break
		var candidate: MapFeature = _propose(a_plan)
		if candidate == null:
			continue
		found += 1
		candidate.realised_share = _share_of.call(candidate.center)
		var score: float = (
			MapFavor.share_error(candidate.realised_share, a_target)
			- (
				_params.collocation_weight
				* a_freedom
				* _collocation(candidate.kind, candidate.center)
			)
		)
		if score < best_score:
			best_score = score
			best = candidate
	if best == null:
		return null
	best.target_share = a_target
	best.plan = a_plan
	_commit(best)
	return best


#region Proposals
## A random origin for a `dims` footprint inside the draw window.
func _random_origin(a_dims: Vector2i) -> Vector2i:
	return Vector2i(
		_rng.randi_range(_window.position.x, maxi(_window.position.x, _window.end.x - a_dims.x)),
		_rng.randi_range(_window.position.y, maxi(_window.position.y, _window.end.y - a_dims.y))
	)


func _propose(a_plan: FeaturePlan) -> MapFeature:
	match a_plan.kind:
		MapFeature.Kind.POND:
			return _propose_pond(a_plan)
		MapFeature.Kind.BUILDING_CLUSTER:
			return _propose_cluster(a_plan)
		MapFeature.Kind.SITE_CLUSTER:
			return _propose_site_cluster(a_plan)
	return _propose_structure(a_plan)


func _propose_structure(a_plan: FeaturePlan) -> MapFeature:
	var dims: Vector2i = a_plan.piece.footprint
	var origin: Vector2i = _random_origin(dims)
	if not _grid.is_rect_free(origin, dims):
		return null
	var center: Vector2 = Vector2(origin) + Vector2(dims) * 0.5
	if not _is_spaced(center):
		return null
	var feature := MapFeature.new()
	feature.kind = a_plan.kind
	feature.value = a_plan.value
	feature.center = center
	feature.placements.append({piece = a_plan.piece, origin = origin})
	return feature


## Grow a 4-connected blob of `pond_cells` cells from a random seed, nearest-first with
## jitter. Every pond cell must keep its rim ring free too, and the pan must hold an
## extractor — a pond nobody can build in is not a resource.
func _propose_pond(a_plan: FeaturePlan) -> MapFeature:
	var seed_cell: Vector2i = _random_origin(Vector2i.ONE)
	if not _is_pond_cell_free(seed_cell):
		return null
	var region: Dictionary = {seed_cell: true}
	var frontier: Dictionary = {}
	_extend_frontier(frontier, region, seed_cell)
	while region.size() < a_plan.pond_cells:
		var next: Vector2i = _nearest_frontier(frontier, seed_cell)
		if next == Vector2i(-1, -1):
			return null
		frontier.erase(next)
		region[next] = true
		_extend_frontier(frontier, region, next)
	_fill_pan_holes(region)
	var cells: Array[Vector2i] = []
	cells.assign(region.keys())
	if not _holds_block(region, _params.site_piece.footprint):
		return null
	var center := Vector2.ZERO
	for cell: Vector2i in cells:
		center += Vector2(cell) + Vector2(0.5, 0.5)
	center /= float(cells.size())
	if not _is_spaced(center):
		return null
	var feature := MapFeature.new()
	feature.kind = MapFeature.Kind.POND
	feature.center = center
	feature.pond_cells = cells
	feature.pond_seed_cell = seed_cell
	feature.pond_richness = a_plan.pond_richness
	# Capped: filling the pan's holes can add a few cells past the planned size, and the charge
	# bounds are a design promise (map-generation.md §Pond sizing and charge).
	feature.pond_charge = mini(cells.size() * a_plan.pond_richness, _params.pond_charge_max)
	feature.value = _params.pond_value(feature.pond_charge)
	var floor_height: float = _params.ground_height - POND_SINK
	feature.pond_level = floor_height + POND_SINK * POND_LEVEL_FRACTION
	return feature


## A cluster candidate is a centre plus a packing of its pieces within the scatter radius,
## each clear of the others by the footprint gap. One member that cannot fit sinks the
## candidate.
func _propose_cluster(a_plan: FeaturePlan) -> MapFeature:
	var center := Vector2(
		_rng.randf_range(_window.position.x, _window.end.x),
		_rng.randf_range(_window.position.y, _window.end.y)
	)
	if not _grid.is_free(Vector2i(center)) or not _is_spaced(center):
		return null
	var radius: float = _cluster_radius(a_plan)
	var taken: Dictionary = {}
	var placements: Array[Dictionary] = []
	for piece: MapPiece in a_plan.cluster_pieces:
		var origin: Vector2i = _fit_cluster_member(piece, center, radius, taken)
		if origin == Vector2i(-1, -1):
			return null
		placements.append({piece = piece, origin = origin})
		for cell: Vector2i in PlacementGrid.rect_cells(
			origin - Vector2i.ONE * _params.footprint_gap_cells,
			piece.footprint + Vector2i.ONE * 2 * _params.footprint_gap_cells
		):
			taken[cell] = true
	if not _is_separated(MapFeature.Kind.BUILDING_CLUSTER, placements):
		return null
	var feature := MapFeature.new()
	feature.kind = MapFeature.Kind.BUILDING_CLUSTER
	feature.value = a_plan.value
	feature.center = center
	feature.placements = placements
	return feature


## Sites edge to edge: the first at random, each next one against a random member already in
## the cluster, on one of its four sides. Every site shares one footprint, so members stand on a
## lattice from the first and two can only overlap by sharing an origin.
func _propose_site_cluster(a_plan: FeaturePlan) -> MapFeature:
	var dims: Vector2i = a_plan.cluster_pieces[0].footprint
	var first: Vector2i = _random_origin(dims)
	if not _grid.is_rect_free(first, dims):
		return null
	var origins: Array[Vector2i] = [first]
	var steps: Array[Vector2i] = [
		Vector2i(dims.x, 0), Vector2i(-dims.x, 0), Vector2i(0, dims.y), Vector2i(0, -dims.y)
	]
	for _member: int in range(1, a_plan.cluster_pieces.size()):
		var next: Vector2i = _adjacent_site(origins, steps, dims)
		if next == Vector2i(-1, -1):
			return null
		origins.append(next)
	var center := Vector2.ZERO
	var placements: Array[Dictionary] = []
	for i: int in origins.size():
		placements.append({piece = a_plan.cluster_pieces[i], origin = origins[i]})
		center += Vector2(origins[i]) + Vector2(dims) * 0.5
	center /= float(origins.size())
	if not _is_spaced(center) or not _is_separated(MapFeature.Kind.SITE_CLUSTER, placements):
		return null
	var feature := MapFeature.new()
	feature.kind = MapFeature.Kind.SITE_CLUSTER
	feature.value = a_plan.value
	feature.center = center
	feature.placements = placements
	return feature


## A free origin edge-adjacent to one of `a_origins`; (-1, -1) when the draws run out.
func _adjacent_site(
	a_origins: Array[Vector2i], a_steps: Array[Vector2i], a_dims: Vector2i
) -> Vector2i:
	for _i: int in SITE_ADJACENCY_DRAWS:
		var next: Vector2i = (
			a_origins[_rng.randi() % a_origins.size()] + a_steps[_rng.randi() % a_steps.size()]
		)
		if not a_origins.has(next) and _grid.is_rect_free(next, a_dims):
			return next
	return Vector2i(-1, -1)


## Least L1 distance between the nearest members of two clusters of `kind`; 0 for a kind that
## sets none.
func _separation_cells(a_kind: MapFeature.Kind) -> int:
	match a_kind:
		MapFeature.Kind.BUILDING_CLUSTER:
			return _params.building_cluster_separation_cells
		MapFeature.Kind.SITE_CLUSTER:
			return _params.site_cluster_separation_cells
	return 0


## Whether every member of a candidate cluster keeps its kind's separation from every member
## of every placed cluster of that kind, by L1 distance between their nearest cells.
func _is_separated(a_kind: MapFeature.Kind, a_placements: Array[Dictionary]) -> bool:
	var separation: int = _separation_cells(a_kind)
	for placement: Dictionary in a_placements:
		var rect := Rect2i(placement.origin, (placement.piece as MapPiece).footprint)
		for other: Rect2i in _cluster_rects.get(a_kind, []):
			if footprint_l1_distance(rect, other) < separation:
				return false
	return true


## L1 distance between the nearest cells of two footprints: 0 when they overlap, 1 when they
## touch along an edge, 2 across a corner.
static func footprint_l1_distance(a: Rect2i, b: Rect2i) -> int:
	var gap_x: int = maxi(0, maxi(b.position.x - a.end.x + 1, a.position.x - b.end.x + 1))
	var gap_z: int = maxi(0, maxi(b.position.y - a.end.y + 1, a.position.y - b.end.y + 1))
	return gap_x + gap_z


## The disc a cluster's members scatter in: its footprints, each grown by the gap, filling
## `cluster_packing_density` of it.
func _cluster_radius(a_plan: FeaturePlan) -> float:
	var area: float = 0.0
	for piece: MapPiece in a_plan.cluster_pieces:
		var padded: Vector2i = piece.footprint + Vector2i.ONE * _params.footprint_gap_cells
		area += padded.x * padded.y
	return sqrt(area / (PI * _params.cluster_packing_density))


func _fit_cluster_member(
	a_piece: MapPiece, a_center: Vector2, a_radius: float, a_taken: Dictionary
) -> Vector2i:
	for _i: int in CLUSTER_MEMBER_DRAWS:
		var offset := Vector2.from_angle(_rng.randf() * TAU) * a_radius * sqrt(_rng.randf())
		var origin := Vector2i((a_center + offset - Vector2(a_piece.footprint) * 0.5).round())
		if not _grid.is_rect_free(origin, a_piece.footprint):
			continue
		var clear: bool = true
		for cell: Vector2i in PlacementGrid.rect_cells(origin, a_piece.footprint):
			if a_taken.has(cell):
				clear = false
				break
		if clear:
			return origin
	return Vector2i(-1, -1)


#endregion


#region Pond growth
## A pond cell needs itself and its whole rim ring free.
func _is_pond_cell_free(a_cell: Vector2i) -> bool:
	for dx: int in range(-POND_RIM_CELLS, POND_RIM_CELLS + 1):
		for dz: int in range(-POND_RIM_CELLS, POND_RIM_CELLS + 1):
			if not _grid.is_free(a_cell + Vector2i(dx, dz)):
				return false
	return true


func _extend_frontier(a_frontier: Dictionary, a_region: Dictionary, a_cell: Vector2i) -> void:
	for step: Vector2i in _NEIGHBOURS:
		var next: Vector2i = a_cell + step
		if a_region.has(next) or a_frontier.has(next) or not _is_pond_cell_free(next):
			continue
		a_frontier[next] = _rng.randf() * POND_GROWTH_NOISE_CELLS


## The frontier cell with the least jittered distance from the seed; (-1, -1) when empty.
func _nearest_frontier(a_frontier: Dictionary, a_seed: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_score: float = INF
	for cell: Vector2i in a_frontier:
		var score: float = Vector2(cell).distance_to(Vector2(a_seed)) + a_frontier[cell]
		if score < best_score:
			best_score = score
			best = cell
	return best


## Add every cell whose four corners the pan lowers anyway. Such a cell is flat at the floor
## and floods, so leaving it out would make the water cover more than the charge was priced on.
static func _fill_pan_holes(region: Dictionary) -> void:
	var lowered: Dictionary = {}
	for cell: Vector2i in region:
		for corner: Vector2i in PlacementGrid.rect_cells(cell, Vector2i(2, 2)):
			lowered[corner] = true
	var holes: Array[Vector2i] = []
	for corner: Vector2i in lowered:
		# Each lowered corner is the min corner of at most one candidate hole cell.
		var cell: Vector2i = corner
		if region.has(cell):
			continue
		if (
			lowered.has(cell + Vector2i(1, 0))
			and lowered.has(cell + Vector2i(0, 1))
			and lowered.has(cell + Vector2i(1, 1))
		):
			holes.append(cell)
	for cell: Vector2i in holes:
		region[cell] = true


## Whether `region` contains a full `dims` rectangle.
static func _holds_block(region: Dictionary, dims: Vector2i) -> bool:
	for cell: Vector2i in region:
		var whole: bool = true
		for block_cell: Vector2i in PlacementGrid.rect_cells(cell, dims):
			if not region.has(block_cell):
				whole = false
				break
		if whole:
			return true
	return false


#endregion


#region Scoring and commit
func _is_spaced(a_center: Vector2) -> bool:
	for feature: MapFeature in _placed:
		if feature.center.distance_to(a_center) < _params.feature_spacing_cells:
			return false
	return true


## Sum of affinities toward placed features within each rule's radius.
func _collocation(a_kind: MapFeature.Kind, a_center: Vector2) -> float:
	var total: float = 0.0
	for feature: MapFeature in _placed:
		var rule: CollocationRule = _rules.get(Vector2i(a_kind, feature.kind))
		if rule != null and feature.center.distance_to(a_center) <= rule.radius_cells:
			total += rule.affinity
	return total


func _commit(a_feature: MapFeature) -> void:
	_placed.append(a_feature)
	if a_feature.kind == MapFeature.Kind.POND:
		_grid.reserve(a_feature.pond_cells, POND_RIM_CELLS + _params.footprint_gap_cells)
	else:
		_grid.reserve(a_feature.structure_cells(), _params.footprint_gap_cells)
	if _separation_cells(a_feature.kind) > 0:
		if not _cluster_rects.has(a_feature.kind):
			_cluster_rects[a_feature.kind] = []
		for placement: Dictionary in a_feature.placements:
			_cluster_rects[a_feature.kind].append(
				Rect2i(placement.origin, (placement.piece as MapPiece).footprint)
			)
#endregion
