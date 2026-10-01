@tool
class_name MapGenerator
extends RefCounted

## Generates a map from parameters and a seed: extent, start ring, resources placed by favor,
## topology (barriers cut and carved, favor corrected by walking distance) and terrain (ponds,
## ridges, flooded chasms) — passes 1-5 of gdd/systems/terrain-and-navigation/map-generation.md.
## MapGenerationParams.last_pass stops it early, so a pass can be inspected alone.
##
## PURE: no scene, no Map, no loaded piece. The shell that writes a scene resolves piece ids and
## supplies the catalog; everything here runs in a bare test. The same seed and parameters
## always produce the same map.
##
## An instance is one run: it holds the seeded generator and the placement state threaded
## through the passes, and is thrown away after `generate`.

#region Constants
## How far snapping a start to whole cells may pull it inside the least distance from the
## centre, as a fraction of the half-extents.
const _SNAP_TOLERANCE_REACH: float = 0.02
## Rounds of currency rebalancing pass 4 may take; each is one sweep over the currency's
## features, and the rounds stop early once one makes no progress.
const _REBALANCE_ROUNDS: int = 3
## Clear cells a feature moved in pass 6 keeps from every other feature: wide enough that their
## reserved rings cannot meet, so neither footprint can take a corner of the other's level.
const _LEVEL_NEIGHBOUR_MARGIN: int = 4
## Dry cells a chasm leaves either side of a level boundary, so its water cannot run down the
## chasm into the level below. Two, because the row touching the water shares its sunk corners
## and can flood itself; the row past that one is what holds.
const _CHASM_LIP_CELLS: int = 2
## Where a body's surface sits between its floor and the ground it is cut into.
const WATER_LEVEL_FRACTION: float = 0.5
## The eight cells around a cell.
const _NEIGHBOURS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
#endregion

#region Properties
var _params: MapGenerationParams
var _rng := RandomNumberGenerator.new()
var _result := GeneratedMap.new()
var _area: PlayArea
var _grid: PlacementGrid
## Cell -> cut, for every lake's shallow shelf; rebuilt with the terrain each time pass 5 shapes
## it, so the water fill knows which shallows belong to which lake.
var _lake_shelf: Dictionary = {}
#endregion


static func generate(params: MapGenerationParams, generation_seed: int) -> GeneratedMap:
	var generator := MapGenerator.new()
	generator._params = params
	generator._rng.seed = generation_seed
	generator._result.generation_seed = generation_seed
	return generator._run()


## Each pass runs only if last_pass reaches it and the pass before succeeded. Balance is
## validated whenever resources were placed, against whatever distances the last pass left.
func _run() -> GeneratedMap:
	# In MapGenerationParams.Pass order, and its values are the pass NUMBERS — so `last_pass`
	# doubles as how many of these to run.
	var passes: Array[Callable] = [
		_make_extent, _place_starts, _place_resources, _run_topology, _realise_terrain,
		_raise_elevation]
	assert(passes.size() == MapGenerationParams.PASS_COUNT,
		"a pass in the Pass enum with nothing here to run would stop the generator early")
	for index: int in mini(_params.last_pass, passes.size()):
		if not passes[index].call():
			return _result
		_result.passes_run = index + 1
	if _result.passes_run >= 3:
		_validate_balance()
	if _result.passes_run >= MapGenerationParams.Pass.TERRAIN:
		_validate_obstruction()
	return _result


## Pass 3.
func _place_resources() -> bool:
	# A map with no energy is unplayable, and would otherwise pass as valid: refuse it.
	if not _energy_total() > 0.0:
		_result.errors.append("the energy budget is %s, so the map would have no ponds or sites"
			% _energy_total())
		return false
	var placer := FeaturePlacer.new(_params, _rng, _grid, _result.starts)
	var pond_plans: Array[FeaturePlan] = _pond_plans()
	var currencies: Array = [
		pond_plans, _site_plans(pond_plans), _shelter_plans(), _building_plans()]
	for plans: Array[FeaturePlan] in currencies:
		if not _place_currency(placer, plans):
			return false
	return true


#region Pass 1 — extent
func _make_extent() -> bool:
	var terrain := TerrainData.new()
	_result.play_size = Vector2i(
		_rng.randi_range(_params.play_size_min, _params.play_size_max),
		_rng.randi_range(_params.play_size_min, _params.play_size_max))
	terrain.play_size = _result.play_size
	var heights := PackedFloat32Array()
	heights.resize(terrain.map_width() * terrain.map_depth())
	heights.fill(_params.ground_height)
	terrain.heights = heights
	_result.terrain = terrain
	# The play rectangle in cell space: the grid's centre is its middle corner.
	var center := Vector2(terrain.grid_width(), terrain.grid_depth()) * 0.5
	_area = PlayArea.screen_aligned(center, terrain.play_half_extents(), Map.CELL_SIZE)
	_grid = PlacementGrid.for_terrain(terrain)
	for z: int in terrain.grid_depth():
		for x: int in terrain.grid_width():
			if terrain.is_cell_in_play(Vector2i(x, z)):
				_result.play_cell_count += 1
	return true
#endregion


#region Pass 2 — starts
## Draw rings until one satisfies every start invariant; fail loudly after the attempt budget.
## Each draw is independent, so this is bounded retry rather than repair.
func _place_starts() -> bool:
	for _attempt: int in _params.start_attempts:
		var starts: Array[MapStart] = _draw_ring()
		if _starts_are_valid(starts):
			_result.starts = starts
			for start: MapStart in starts:
				_grid.reserve(PlacementGrid.rect_cells(_clearance_origin(start), _clearance_dims()), 0)
			return true
	_result.errors.append("no start ring satisfied the start invariants in %d attempts"
		% _params.start_attempts)
	return false


## Equal angular spacing about the play-area centre, jittered in angle. Along each start's
## bearing the distance is drawn uniformly between the least distance from the centre and the
## most the edge margin allows, measured on an ellipse with the play rectangle's aspect. Starts
## of one alliance are adjacent in angle. Each start is snapped so its clearance square sits on
## whole cells, centred on it.
func _draw_ring() -> Array[MapStart]:
	var count: int = _params.start_count()
	var spacing: float = TAU / float(count)
	var base_angle: float = _rng.randf() * TAU
	var starts: Array[MapStart] = []
	for i: int in count:
		var angle: float = base_angle + spacing * (
			i + _rng.randf_range(-1.0, 1.0) * _params.start_angle_jitter_fraction)
		var bearing: Vector2 = Vector2.from_angle(angle)
		var reach: float = _rng.randf_range(_min_reach(), maxf(_min_reach(), _max_reach(bearing)))
		var point: Vector2 = _area.to_world(bearing * _area.half * reach)
		var start := MapStart.at(point, i / _params.starts_per_alliance)
		start.position = Vector2(_clearance_origin(start)) + Vector2(_clearance_dims()) * 0.5
		starts.append(start)
	return starts


## Least distance from the centre as a fraction of the half-extent: a fraction of the SIDE is
## twice that of the half.
func _min_reach() -> float:
	return 2.0 * _params.start_min_center_fraction


## Furthest along `bearing` (as a fraction of the half-extents) a start may stand and keep its
## edge margin.
func _max_reach(a_bearing: Vector2) -> float:
	var margin: float = _params.start_edge_margin_cells
	var reach: float = INF
	if not is_zero_approx(a_bearing.x):
		reach = minf(reach, (_area.half.x - margin) / (absf(a_bearing.x) * _area.half.x))
	if not is_zero_approx(a_bearing.y):
		reach = minf(reach, (_area.half.y - margin) / (absf(a_bearing.y) * _area.half.y))
	return reach


## Distance of `point` from the centre on the play rectangle's ellipse, as a fraction of the
## half-extents — what _min_reach bounds.
func _reach_of(a_point: Vector2) -> float:
	var local: Vector2 = _area.to_local(a_point)
	return (local / _area.half).length()


func _starts_are_valid(a_starts: Array[MapStart]) -> bool:
	var separation: float = _params.start_separation_diagonal_fraction * _area.diagonal() \
		* sqrt(2.0 / float(a_starts.size()))
	for i: int in a_starts.size():
		var local: Vector2 = _area.to_local(a_starts[i].position)
		if absf(local.x) > _area.half.x - _params.start_edge_margin_cells \
				or absf(local.y) > _area.half.y - _params.start_edge_margin_cells:
			return false
		# Snapping to whole cells can pull a start a fraction of a cell inward.
		if _reach_of(a_starts[i].position) < _min_reach() - _SNAP_TOLERANCE_REACH:
			return false
		if not _grid.is_rect_free(_clearance_origin(a_starts[i]), _clearance_dims()):
			return false
		for j: int in range(i + 1, a_starts.size()):
			if a_starts[i].position.distance_to(a_starts[j].position) < separation:
				return false
	return true


## The start's clear box is reserved in the placement grid, which is what keeps every feature
## and every pond pan — the only terrain generation shapes — out of it.
func _clearance_dims() -> Vector2i:
	return Vector2i.ONE * 2 * _params.start_clear_radius_cells


func _clearance_origin(a_start: MapStart) -> Vector2i:
	return Vector2i((a_start.position - Vector2(_clearance_dims()) * 0.5).round())
#endregion


#region Pass 3 — plans
## Ponds up to their share of the energy budget, largest first so the small ones at the end
## fine-tune the balance. Ponds and sites are balanced as separate currencies.
func _pond_plans() -> Array[FeaturePlan]:
	var budget: float = _energy_total() * _params.pond_value_fraction
	var plans: Array[FeaturePlan] = []
	var pond_value: float = 0.0
	while pond_value < budget:
		var plan: FeaturePlan = _pond_plan()
		pond_value += plan.value
		plans.append(plan)
	plans.sort_custom(func(a: FeaturePlan, b: FeaturePlan) -> bool: return a.value > b.value)
	return plans


func _energy_total() -> float:
	# Per PLAYER: a team game gives every player as much as a duel. Placement still balances
	# access per alliance, whose share is then its members' sum.
	return _params.energy_value_per_player * _params.start_count()


## Site clusters for the energy the ponds left, largest first.
func _site_plans(a_pond_plans: Array[FeaturePlan]) -> Array[FeaturePlan]:
	var pond_value: float = 0.0
	for plan: FeaturePlan in a_pond_plans:
		pond_value += plan.value
	var plans: Array[FeaturePlan] = []
	var site_count: int = maxi(0, roundi((_energy_total() - pond_value) / _params.site_value()))
	var triple_fraction: float = _rng.randf_range(
		_params.site_triple_fraction_min, _params.site_triple_fraction_max)
	var pair_fraction: float = _rng.randf_range(
		_params.site_pair_fraction_min, _params.site_pair_fraction_max)
	for size: int in site_cluster_sizes(_rng, site_count, triple_fraction, pair_fraction):
		var plan := FeaturePlan.new()
		plan.kind = MapFeature.Kind.SITE_CLUSTER
		for _i: int in size:
			plan.cluster_pieces.append(_params.site_piece)
		plan.value = size * _params.site_value()
		plans.append(plan)
	plans.sort_custom(func(a: FeaturePlan, b: FeaturePlan) -> bool: return a.value > b.value)
	return plans


## Split `site_count` sites into clusters of three, two and one: in expectation
## `triple_fraction` of the sites in threes and `pair_fraction` in twos, the rest alone.
##
## Each cluster count is rounded STOCHASTICALLY — 1.4 threes is one three, plus a second with
## chance 0.4 — because a map has only a handful of sites and flooring would round every
## fraction below one cluster away. Threes are taken first and capped by what is left, so the
## sizes always sum to `site_count`.
static func site_cluster_sizes(
	rng: RandomNumberGenerator, site_count: int, triple_fraction: float, pair_fraction: float
) -> Array[int]:
	var triples: int = mini(_stochastic_round(rng, site_count * triple_fraction / 3.0), site_count / 3)
	var left: int = site_count - 3 * triples
	var pairs: int = mini(_stochastic_round(rng, site_count * pair_fraction / 2.0), left / 2)
	var sizes: Array[int] = []
	for _i: int in triples:
		sizes.append(3)
	for _i: int in pairs:
		sizes.append(2)
	for _i: int in left - 2 * pairs:
		sizes.append(1)
	return sizes


static func _stochastic_round(rng: RandomNumberGenerator, value: float) -> int:
	var whole: int = floori(value)
	return whole + (1 if rng.randf() < value - whole else 0)


## Size from the right-skewed draw; richness drawn with rich categories fading as size grows.
func _pond_plan() -> FeaturePlan:
	var plan := FeaturePlan.new()
	plan.kind = MapFeature.Kind.POND
	# CHARGE FIRST: how long the pond lasts is the design target (3 to 8 minutes for one
	# extractor). Then a richness category that can hold that charge within its own size bounds,
	# and the size follows as charge over richness, so a rich pond is compact.
	var charge: float = GenerationRandom.skew_normal(_rng,
		_params.pond_charge_location, _params.pond_charge_scale, _params.pond_charge_skew,
		_params.pond_charge_min, _params.pond_charge_max)
	var category: int = _pond_category(charge)
	plan.pond_richness = _params.pond_richness_factors[category]
	plan.pond_cells = clampi(roundi(charge / plan.pond_richness),
		maxi(_params.pond_richness_cells_min[category], _params.pond_cells_min),
		mini(_params.pond_richness_cells_max[category], _params.pond_cells_max))
	plan.value = _params.pond_value(plan.pond_cells * plan.pond_richness)
	return plan


## A richness category for a pond of `a_charge`, drawn by weight among the categories whose size
## bounds can hold it. Falls back to the nearest fit when none can, so a parameter mistake bends a
## pond's charge rather than failing generation.
func _pond_category(a_charge: float) -> int:
	var weights := PackedFloat32Array()
	var any_fits: bool = false
	for k: int in _params.pond_richness_factors.size():
		var cells: float = a_charge / _params.pond_richness_factors[k]
		var fits: bool = cells >= _params.pond_richness_cells_min[k] - 0.5 \
			and cells <= _params.pond_richness_cells_max[k] + 0.5
		weights.append(_params.pond_richness_weights[k] if fits else 0.0)
		any_fits = any_fits or fits
	if any_fits:
		return GenerationRandom.weighted_index(_rng, weights)
	var nearest: int = 0
	var nearest_gap: float = INF
	for k: int in _params.pond_richness_factors.size():
		var cells: float = a_charge / _params.pond_richness_factors[k]
		var gap: float = maxf(_params.pond_richness_cells_min[k] - cells,
			cells - _params.pond_richness_cells_max[k])
		if gap < nearest_gap:
			nearest_gap = gap
			nearest = k
	return nearest


func _shelter_plans() -> Array[FeaturePlan]:
	var count: int = roundi(_params.alliance_count * (
		_params.shelters_per_alliance_min + _params.shelters_per_alliance_extra * _rng.randf()))
	var plans: Array[FeaturePlan] = []
	for _i: int in count:
		var plan := FeaturePlan.new()
		plan.kind = MapFeature.Kind.SHELTER
		plan.piece = _params.shelter_piece
		plan.value = 1.0
		plans.append(plan)
	return plans


## A garrison-capacity budget per player, then clusters drawn until it is spent, each packed to
## a drawn capacity. The last cluster is cut short at the budget, so the total overshoots by less
## than one building. A cluster's balance value is its capacity.
func _building_plans() -> Array[FeaturePlan]:
	var plans: Array[FeaturePlan] = []
	if _params.building_pool.is_empty():
		return plans
	var total: float = _params.building_capacity_per_player * _params.start_count()
	var planned: float = 0.0
	while planned < total:
		var plan := FeaturePlan.new()
		plan.kind = MapFeature.Kind.BUILDING_CLUSTER
		var capacity: float = cluster_capacity(_rng, _params.cluster_capacity_band_edges,
			_params.cluster_capacity_band_weights)
		var weights: PackedFloat32Array = building_weights(_params.building_pool,
			_params.cluster_capacity_band_edges, _params.cluster_large_building_bias, capacity)
		var remaining: float = capacity
		while remaining > 0.0 and planned < total:
			var index: int = GenerationRandom.weighted_index(
				_rng, _fitting_weights(weights, remaining))
			if index < 0:
				break
			var piece: MapPiece = _params.building_pool[index]
			plan.cluster_pieces.append(piece)
			plan.value += piece.capacity
			planned += maxi(piece.capacity, 1)
			# At least 1, so a piece with no garrison still fills its cluster and ends it.
			remaining -= maxi(piece.capacity, 1)
		if plan.cluster_pieces.is_empty():
			# Nothing in the pool fits the drawn capacity; the smallest piece stands alone.
			var smallest: MapPiece = _smallest_building()
			plan.cluster_pieces.append(smallest)
			plan.value = smallest.capacity
			planned += maxi(smallest.capacity, 1)
		plans.append(plan)
	plans.sort_custom(func(a: FeaturePlan, b: FeaturePlan) -> bool: return a.value > b.value)
	return plans


## A cluster's garrison capacity: band i (edges i to i+1) by `weights`, then uniformly within it.
static func cluster_capacity(
	rng: RandomNumberGenerator, edges: PackedInt32Array, weights: PackedFloat32Array
) -> float:
	var band: int = GenerationRandom.weighted_index(rng, weights)
	return rng.randf_range(edges[band], edges[band + 1])


## `pool`'s draw weights for a cluster of `capacity`: each piece's weight times
## capacity^(bias × t), t the cluster's capacity across `edges` in [0, 1], so a cluster leans
## toward large buildings as it climbs the bands.
static func building_weights(
	pool: Array[MapPiece], edges: PackedInt32Array, bias: float, capacity: float
) -> PackedFloat32Array:
	var t: float = clampf(
		inverse_lerp(float(edges[0]), float(edges[edges.size() - 1]), capacity), 0.0, 1.0)
	var weights := PackedFloat32Array()
	for piece: MapPiece in pool:
		weights.append(piece.weight * pow(maxf(piece.capacity, 1.0), bias * t))
	return weights


## `a_weights` with every piece zeroed that would carry the cluster more than the overshoot past
## `a_remaining`.
func _fitting_weights(a_weights: PackedFloat32Array, a_remaining: float) -> PackedFloat32Array:
	var fitting := PackedFloat32Array()
	for i: int in a_weights.size():
		var fits: bool = _params.building_pool[i].capacity \
			<= a_remaining + _params.cluster_capacity_overshoot
		fitting.append(a_weights[i] if fits else 0.0)
	return fitting


func _smallest_building() -> MapPiece:
	var smallest: MapPiece = _params.building_pool[0]
	for piece: MapPiece in _params.building_pool:
		if piece.capacity < smallest.capacity:
			smallest = piece
	return smallest
#endregion


#region Pass 3 — placement
## Place one currency's plans in order, each aimed at a random share steered toward what the
## remaining plans still owe every alliance.
func _place_currency(a_placer: FeaturePlacer, a_plans: Array[FeaturePlan]) -> bool:
	var k: int = _params.alliance_count
	var remaining: float = 0.0
	for plan: FeaturePlan in a_plans:
		remaining += plan.value
	var target_each: float = remaining / float(k)
	var realised := PackedFloat32Array()
	realised.resize(k)
	for index: int in a_plans.size():
		var plan: FeaturePlan = a_plans[index]
		var raw: PackedFloat32Array = GenerationRandom.dirichlet(_rng, k, _params.favor_concentration)
		var freedom: float = (remaining - plan.value) / remaining if remaining > 0.0 else 0.0
		var target: PackedFloat32Array = MapFavor.steer(
			raw, _desired_share(realised, target_each, remaining), freedom)
		var feature: MapFeature = a_placer.place(plan, target, freedom)
		if feature == null:
			_result.errors.append("no valid position for %s %d of %d — the map is too full" % [
				MapFeature.Kind.keys()[plan.kind], index + 1, a_plans.size()])
			return false
		_result.features.append(feature)
		# A pond's value is re-priced from the cells it actually grew.
		remaining -= plan.value
		for a: int in k:
			realised[a] += feature.value * feature.realised_share[a]
	return true


## The share the remaining value must deliver for every alliance to land on its target.
func _desired_share(
	a_realised: PackedFloat32Array, a_target_each: float, a_remaining: float
) -> PackedFloat32Array:
	var k: int = a_realised.size()
	var desired := PackedFloat32Array()
	desired.resize(k)
	var total: float = 0.0
	for a: int in k:
		desired[a] = 1.0 / k if a_remaining <= 0.0 \
			else clampf((a_target_each - a_realised[a]) / a_remaining, 0.0, 1.0)
		total += desired[a]
	for a: int in k:
		desired[a] = desired[a] / total if total > 0.0 else 1.0 / k
	return desired
#endregion


#region Pass 4 — topology
## Cut and carve, then move any feature the barriers pushed off its favor.
func _run_topology() -> bool:
	var topology: MapTopology = MapTopology.run(
		_params, _rng, _result.terrain, _grid, _result.starts, _result.features)
	_result.topology = topology
	if not topology.errors.is_empty():
		_result.errors.append_array(topology.errors)
		return false
	return _correct_favor(topology)


## Re-measure every feature's share by walking distance, and move each that drifted more than
## favor_tolerance from its target to the best spot within correction_radius — kept only if it
## lands nearer its target. The invariant is per currency (_validate_balance, by these walking
## shares), not per feature: features are aimed at deliberately leaning targets, and one that
## cannot be brought back is only a failure if its currency ends up unfair.
func _correct_favor(a_topology: MapTopology) -> bool:
	var fields: Array[PathField] = _alliance_fields(a_topology.passable_mask())
	var share_of: Callable = func(point: Vector2) -> PackedFloat32Array:
		return _walking_share(fields, Vector2i(point.floor()))
	for index: int in _result.features.size():
		var feature: MapFeature = _result.features[index]
		feature.realised_share = share_of.call(feature.center)
		var drift: float = MapFavor.share_error(feature.realised_share, feature.target_share)
		if drift <= _params.favor_tolerance:
			continue
		var moved: MapFeature = _replace_feature(index, _topology_blocked(a_topology), 0, share_of)
		if moved != null \
				and MapFavor.share_error(moved.realised_share, moved.target_share) < drift:
			_result.features[index] = moved
	for currency: int in MapFeature.Currency.values():
		for _round: int in _REBALANCE_ROUNDS:
			var before: float = _currency_deviation(currency)
			if before <= _params.favor_tolerance:
				break
			_rebalance_currency(currency, _topology_blocked(a_topology), 0, share_of)
			if _currency_deviation(currency) >= before:
				break
	return true


## Small drifts across many features can leave a currency unfair when no single one drifted
## far. For such a currency, re-aim its features, largest first, at the share that would even it
## out given the rest, keeping each move that shrinks the imbalance, until it is within tolerance.
func _rebalance_currency(
	a_currency: int, a_blocked: Array[Vector2i], a_neighbour_margin: int, a_share_of: Callable
) -> void:
	var indices: Array[int] = []
	for i: int in _result.features.size():
		if _result.features[i].currency() == a_currency:
			indices.append(i)
	indices.sort_custom(func(a: int, b: int) -> bool:
		return _result.features[a].value > _result.features[b].value)
	for index: int in indices:
		var deviation: float = _currency_deviation(a_currency)
		if deviation <= _params.favor_tolerance:
			return
		var feature: MapFeature = _result.features[index]
		var others := PackedFloat32Array()
		others.resize(_params.alliance_count)
		var total: float = 0.0
		for i: int in indices:
			var other: MapFeature = _result.features[i]
			total += other.value
			if i == index:
				continue
			for a: int in _params.alliance_count:
				others[a] += other.value * other.realised_share[a]
		var held_target: PackedFloat32Array = feature.target_share
		feature.target_share = _desired_share(others, total / _params.alliance_count, feature.value)
		var moved: MapFeature = _replace_feature(index, a_blocked, a_neighbour_margin, a_share_of)
		feature.target_share = held_target
		if moved == null:
			continue
		_result.features[index] = moved
		if _currency_deviation(a_currency) >= deviation:
			_result.features[index] = feature


## Worst relative deviation of any alliance's accessible value in `a_currency` from even.
func _currency_deviation(a_currency: int) -> float:
	var features: Array[MapFeature] = []
	features.assign(_result.features.filter(
		func(f: MapFeature) -> bool: return f.currency() == a_currency))
	var accessible: PackedFloat32Array = MapFavor.accessible_value(features, _params.alliance_count)
	var total: float = 0.0
	for value: float in accessible:
		total += value
	return MapFavor.worst_deviation(accessible, total / _params.alliance_count)


## Cells a moved feature must keep clear of after pass 4: barriers and carved passages.
static func _topology_blocked(a_topology: MapTopology) -> Array[Vector2i]:
	var blocked: Array[Vector2i] = []
	blocked.assign(a_topology.barrier_of.keys() + a_topology.carved_cells.keys())
	return blocked


## One distance field per alliance, seeded at its starts.
func _alliance_fields(a_passable: PackedByteArray) -> Array[PathField]:
	var fields: Array[PathField] = []
	for alliance: int in _params.alliance_count:
		var seeds: Array[Vector2i] = []
		for start: MapStart in _result.starts:
			if start.alliance == alliance:
				seeds.append(Vector2i(start.position.floor()))
		fields.append(PathField.from_seeds(a_passable, _grid.width, _grid.depth, seeds))
	return fields


## Access share by walking distance: MapFavor's inverse-distance rule, over path lengths. An
## alliance that cannot reach the cell gets none of it.
static func _walking_share(fields: Array[PathField], cell: Vector2i) -> PackedFloat32Array:
	var share := PackedFloat32Array()
	var total: float = 0.0
	for field: PathField in fields:
		var d: float = field.distance(cell)
		share.append(0.0 if is_inf(d) else 1.0 / maxf(d, MapFavor.MIN_DISTANCE_CELLS))
		total += share[share.size() - 1]
	for a: int in share.size():
		share[a] = share[a] / total if total > 0.0 else 0.0
	return share


## Place feature `a_index` again near where it stood, with everything else — starts, the other
## features, barriers and carved passages — holding its ground. Null if nothing fits.
func _replace_feature(
	a_index: int, a_blocked: Array[Vector2i], a_neighbour_margin: int, a_share_of: Callable
) -> MapFeature:
	var feature: MapFeature = _result.features[a_index]
	var grid := PlacementGrid.for_terrain(_result.terrain)
	for start: MapStart in _result.starts:
		grid.reserve(PlacementGrid.rect_cells(_clearance_origin(start), _clearance_dims()), 0)
	# A barrier's border cells are steep, and one more cell keeps the footprint gap.
	grid.reserve(a_blocked, 1 + _params.footprint_gap_cells)
	var placer := FeaturePlacer.new(_params, _rng, grid, _result.starts)
	var others: Array[MapFeature] = []
	for i: int in _result.features.size():
		if i != a_index:
			others.append(_result.features[i])
			if a_neighbour_margin > 0:
				grid.reserve(_result.features[i].structure_cells() + _result.features[i].pond_cells,
					a_neighbour_margin)
	placer.adopt(others)
	placer.restrict(feature.center, _params.correction_radius_cells, a_share_of)
	return placer.place(feature.plan, feature.target_share, 0.0)
#endregion


#region Pass 5 — terrain
## Sink the ponds, raise the ridges, sink and flood the chasms, then check enough ground is
## still buildable.
func _realise_terrain() -> bool:
	_shape_terrain(PackedFloat32Array())
	return _check_flat_fraction()


## Build the heights from flat ground: pond pans, ridges and chasms, each relative to the ground,
## then `a_offsets` (pass 6's level per corner; empty for none) added to every corner. Water
## levels move with the ground they stand on. Rebuilt whole rather than patched, so pass 6 sees
## exactly what pass 5 would have made and changes only the level under it.
func _shape_terrain(a_offsets: PackedFloat32Array) -> void:
	var terrain: TerrainData = _result.terrain
	var width: int = terrain.map_width()
	var heights := PackedFloat32Array()
	heights.resize(width * terrain.map_depth())
	heights.fill(_params.ground_height)
	var pan: float = _params.ground_height - FeaturePlacer.POND_SINK
	for feature: MapFeature in _result.features_of(MapFeature.Kind.POND):
		for cell: Vector2i in feature.pond_cells:
			for corner: Vector2i in PlacementGrid.rect_cells(cell, Vector2i(2, 2)):
				heights[corner.y * width + corner.x] = pan
		feature.pond_level = pan + FeaturePlacer.POND_SINK * FeaturePlacer.POND_LEVEL_FRACTION \
			+ _offset_at(a_offsets, feature.pond_seed_cell, width)
	var topology: MapTopology = _result.topology
	var chasm_cells: Dictionary = {}
	_lake_shelf.clear()
	if topology != null:
		var depth_of: Dictionary = _mountain_depths(topology)
		for cell: Vector2i in topology.barrier_of:
			var is_chasm: bool = topology.flooded[topology.barrier_of[cell]]
			if is_chasm:
				chasm_cells[cell] = topology.barrier_of[cell]
			var rise: float = minf((depth_of.get(cell, 1) - 1) * _params.mountain_rise_per_cell,
				_params.mountain_rise_max)
			for corner: Vector2i in PlacementGrid.rect_cells(cell, Vector2i(2, 2)):
				var roughness: float = MapGenerationParams.RIDGE_ROUGHNESS \
					if (corner.x + corner.y) % 2 == 0 else 0.0
				heights[corner.y * width + corner.x] = \
					_params.ground_height - _params.chasm_depth if is_chasm \
					else maxf(heights[corner.y * width + corner.x],
						_params.ground_height + _params.ridge_height + roughness + rise)
		_lake_shelf = _lake_shelves(topology)
		for cell: Vector2i in _lake_shelf:
			for corner: Vector2i in PlacementGrid.rect_cells(cell, Vector2i(2, 2)):
				var index: int = corner.y * width + corner.x
				heights[index] = minf(heights[index], pan)
	if not a_offsets.is_empty():
		for i: int in heights.size():
			heights[i] += a_offsets[i]
	terrain.heights = heights
	_flood_chasms(chasm_cells, width)


## Per grown ridge cell, its distance in cells from the mountain's edge: 1 on the edge.
static func _mountain_depths(topology: MapTopology) -> Dictionary:
	var depth_of: Dictionary = {}
	var frontier: Array[Vector2i] = []
	for cell: Vector2i in topology.barrier_of:
		var cut: int = topology.barrier_of[cell]
		if not topology.grown[cut] or topology.flooded[cut]:
			continue
		for step: Vector2i in _NEIGHBOURS:
			if topology.barrier_of.get(cell + step, -1) != cut:
				depth_of[cell] = 1
				frontier.append(cell)
				break
	var head: int = 0
	while head < frontier.size():
		var at: Vector2i = frontier[head]
		head += 1
		for step: Vector2i in _NEIGHBOURS:
			var next: Vector2i = at + step
			if topology.barrier_of.get(next, -1) == topology.barrier_of[at] \
					and not depth_of.has(next):
				depth_of[next] = depth_of[at] + 1
				frontier.append(next)
	return depth_of


## Per lake, the free ground within lake_shelf_cells of its deep core: sunk to a pond's pan, so
## its water is shallow. Kept off reserved ground like any barrier cell.
func _lake_shelves(a_topology: MapTopology) -> Dictionary:
	var shelf: Dictionary = {}
	var reach: int = _params.lake_shelf_cells
	for cell: Vector2i in a_topology.barrier_of:
		var cut: int = a_topology.barrier_of[cell]
		if not (a_topology.grown[cut] and a_topology.flooded[cut]):
			continue
		for dx: int in range(-reach, reach + 1):
			for dz: int in range(-reach, reach + 1):
				var near: Vector2i = cell + Vector2i(dx, dz)
				if shelf.has(near) or a_topology.barrier_of.has(near) \
						or not _result.terrain.is_cell_in_play(near) \
						or not a_topology.is_barrier_eligible(near):
					continue
				shelf[near] = cut
	return shelf


## Corner offset under a cell's minimum corner; 0 without offsets.
static func _offset_at(offsets: PackedFloat32Array, cell: Vector2i, width: int) -> float:
	return 0.0 if offsets.is_empty() else offsets[cell.y * width + cell.x]


## One water body per level: a chasm is lifted onto levels like any barrier, and water fills
## everything connected below its surface, so a chasm crossing a cliff would pour into every
## level under it (three of five review maps came out 55-88% flooded). Each stretch at one level
## holds its own water instead, at its own ground's depth.
##
## **The chasm stops _CHASM_LIP_CELLS short of a level boundary and that gap stays DRY**, or the
## water would simply run down the chasm into the level below. The gap spans the step, so it is
## cliff: impassable, and the barrier still divides. It is also where a waterfall goes when one
## is built (§6, deferred).
func _flood_chasms(a_cells: Dictionary, a_width: int) -> void:
	_result.chasm_waters.clear()
	var terrain: TerrainData = _result.terrain
	var heights: PackedFloat32Array = terrain.heights
	var offset_of: Dictionary = _level_chasm_cells(a_cells, a_width)
	for cell: Vector2i in offset_of:
		var floor_height: float = _params.ground_height + offset_of[cell] - _params.chasm_depth
		for corner: Vector2i in PlacementGrid.rect_cells(cell, Vector2i(2, 2)):
			var index: int = corner.y * a_width + corner.x
			heights[index] = minf(heights[index], floor_height)
	terrain.heights = heights
	# One water per 4-CONNECTED stretch, because that is how a basin fills: an arm joined only
	# across a corner takes no water from the other's seed, and would be walkable chasm.
	var seen: Dictionary = {}
	for cell: Vector2i in offset_of:
		if seen.has(cell):
			continue
		_chasm_stretch(cell, offset_of, seen)
		var cut: int = a_cells[cell]
		var is_lake: bool = _result.topology.grown[cut]
		# A lake stands at a pond's level, so its shelf is shallow; a river halfway up its chasm.
		var level: float = _params.ground_height + offset_of[cell] + (
			FeaturePlacer.POND_SINK * (FeaturePlacer.POND_LEVEL_FRACTION - 1.0) if is_lake
			else -_params.chasm_depth * WATER_LEVEL_FRACTION)
		var holds: Dictionary = a_cells.merged(_lake_shelf) if is_lake else a_cells
		if _water_escapes(cell, level, holds):
			continue  # a dry chasm: still a barrier, just without water
		_result.chasm_waters.append({seed_cell = cell, level = level})


## Whether water seeded at `a_cell` reaches ground that is not chasm. A chasm beside a cliff
## stands above the level under it, and cliff cells are steep but not TALL — their middle can sit
## under the water, so a fill walks straight over them and drowns everything below. Predicting
## that from the rim heights alone means re-deriving the fill, so the fill itself is the test:
## a body that will not stay in its chasm is not placed, and the chasm is left dry.
func _water_escapes(a_cell: Vector2i, a_level: float, a_chasm: Dictionary) -> bool:
	var basin: WaterBasin = WaterBasin.fill(_result.terrain, a_cell, a_level)
	for cell: Vector2i in basin.depth_by_cell:
		if a_chasm.has(cell):
			continue
		# The ring touching the chasm shares its sunk corners, so it floods with it.
		var is_rim: bool = false
		for dx: int in range(-1, 2):
			for dz: int in range(-1, 2):
				is_rim = is_rim or a_chasm.has(cell + Vector2i(dx, dz))
		if not is_rim:
			return true
	return false


## The chasm cells that hold water, each with the level offset it sits at: those whose four
## corners share one offset, less the ones within _CHASM_LIP_CELLS of a cell that straddles two
## levels. A chasm cell touching a RIDGE is dry too — it stands on the ridge's raised corners and
## is steep rather than deep — but it is not a lip, so the chasm either side of it still floods.
func _level_chasm_cells(a_cells: Dictionary, a_width: int) -> Dictionary:
	var ridge_corners: Dictionary = {}
	for cell: Vector2i in _result.topology.barrier_of:
		if not a_cells.has(cell):
			for corner: Vector2i in PlacementGrid.rect_cells(cell, Vector2i(2, 2)):
				ridge_corners[corner] = true
	var offsets: PackedFloat32Array = _result.elevation.offsets if _result.elevation != null \
		else PackedFloat32Array()
	var offset_of: Dictionary = {}
	var straddling: Dictionary = {}
	for cell: Vector2i in a_cells:
		var corners: Array[Vector2i] = PlacementGrid.rect_cells(cell, Vector2i(2, 2))
		var offset: float = _offset_at(offsets, corners[0], a_width)
		var is_level: bool = true
		var meets_ridge: bool = false
		for corner: Vector2i in corners:
			is_level = is_level and is_equal_approx(_offset_at(offsets, corner, a_width), offset)
			meets_ridge = meets_ridge or ridge_corners.has(corner)
		if not is_level:
			straddling[cell] = true  # the lip: its neighbours give up their water too
		elif not meets_ridge:
			offset_of[cell] = offset
	for cell: Vector2i in straddling:
		for dx: int in range(-_CHASM_LIP_CELLS, _CHASM_LIP_CELLS + 1):
			for dz: int in range(-_CHASM_LIP_CELLS, _CHASM_LIP_CELLS + 1):
				offset_of.erase(cell + Vector2i(dx, dz))
	return offset_of


## The 4-connected chasm cells reached from `a_from`, marked in `a_seen`.
static func _chasm_stretch(a_from: Vector2i, cells: Dictionary, seen: Dictionary) -> void:
	var stretch: Array[Vector2i] = [a_from]
	seen[a_from] = true
	var index: int = 0
	while index < stretch.size():
		var at: Vector2i = stretch[index]
		index += 1
		for step: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
			var next: Vector2i = at + step
			if cells.has(next) and not seen.has(next):
				seen[next] = true
				stretch.append(next)


## The terrain invariant: at least flat_fraction of in-play walkable cells are buildable.
func _check_flat_fraction() -> bool:
	var terrain: TerrainData = _result.terrain
	var walkable: int = 0
	var flat: int = 0
	for z: int in terrain.grid_depth():
		for x: int in terrain.grid_width():
			var cell := Vector2i(x, z)
			if not terrain.is_cell_in_play(cell) \
					or terrain.cell_height_spread(cell) > TerrainGrid.MAX_SLOPE_DIFF:
				continue
			walkable += 1
			flat += 1 if terrain.cell_is_flat(cell) else 0
	if walkable > 0 and float(flat) / walkable < _params.flat_fraction:
		_result.errors.append("only %.0f%% of walkable ground is buildable (least %.0f%%)"
			% [100.0 * flat / walkable, 100.0 * _params.flat_fraction])
		return false
	return true
#endregion


#region Pass 6 — elevation
## Give every region a level, cliff the steps, ramp them for routes and connectivity, rebuild the
## terrain on its levels, and re-measure favor by the walking distances that leaves. Features are
## not moved here: a currency the cliffs leave unfair fails the balance check.
func _raise_elevation() -> bool:
	var elevation: MapElevation = MapElevation.run(_params, _rng, _result.terrain,
		_result.topology, _result.starts.size(), _owned_zones())
	_result.elevation = elevation
	if not elevation.errors.is_empty():
		_result.errors.append_array(elevation.errors)
		return false
	_rebalance_on_levels(elevation)
	if not elevation.errors.is_empty():
		_result.errors.append_array(elevation.errors)
		return false
	_shape_terrain(elevation.offsets)
	return _check_flat_fraction()


## Re-measure favor by the walking distances the cliffs leave, and rebalance any currency that
## is now unfair as pass 4 does — moving features, but only onto ground well clear of cliffs,
## ramps and other features, so each lands within one level. The reserved ground is then
## re-derived from where features stand and connectivity re-checked.
func _rebalance_on_levels(a_elevation: MapElevation) -> void:
	var fields: Array[PathField] = _alliance_fields(a_elevation.passable_mask())
	var share_of: Callable = func(point: Vector2) -> PackedFloat32Array:
		return _walking_share(fields, Vector2i(point.floor()))
	for feature: MapFeature in _result.features:
		feature.realised_share = share_of.call(feature.center)
	var blocked: Array[Vector2i] = _topology_blocked(_result.topology)
	blocked.append_array(a_elevation.cliff_cells.keys())
	for corner: Vector2i in a_elevation.ramp_offsets:
		blocked.append(corner)
	var moved_any: bool = false
	for currency: int in MapFeature.Currency.values():
		for _round: int in _REBALANCE_ROUNDS:
			var before: float = _currency_deviation(currency)
			if before <= _params.favor_tolerance:
				break
			moved_any = true
			_rebalance_currency(currency, blocked, _LEVEL_NEIGHBOUR_MARGIN, share_of)
			if _currency_deviation(currency) >= before:
				break
	if moved_any:
		a_elevation.reown(_owned_zones())


## Per graph node, the cells it reserves plus the ring whose corners they share: a start's box,
## a structure footprint, or a pond pan with its rim. Pass 6 keeps each of these on one level.
func _owned_zones() -> Array:
	var zones: Array = []
	for start: MapStart in _result.starts:
		zones.append(_grown(PlacementGrid.rect_cells(_clearance_origin(start), _clearance_dims()), 1))
	for feature: MapFeature in _result.features:
		if feature.kind == MapFeature.Kind.POND:
			zones.append(_grown(feature.pond_cells, FeaturePlacer.POND_RIM_CELLS + 1))
		else:
			zones.append(_grown(feature.structure_cells(), 1))
	return zones


static func _grown(cells: Array[Vector2i], margin: int) -> Array[Vector2i]:
	var seen: Dictionary = {}
	for cell: Vector2i in cells:
		for dx: int in range(-margin, margin + 1):
			for dz: int in range(-margin, margin + 1):
				seen[cell + Vector2i(dx, dz)] = true
	var grown: Array[Vector2i] = []
	grown.assign(seen.keys())
	return grown


## The traversable share within traversable_tolerance of its target, and impassable ground
## within obstruction_tolerance of even between alliances. Measured on the finished terrain: a
## cell is traversable when it is in play, not steep, not under deep water and not a footprint.
func _validate_obstruction() -> void:
	var terrain: TerrainData = _result.terrain
	var deep: Dictionary = {}
	for water: Dictionary in _result.chasm_waters:
		var basin: WaterBasin = WaterBasin.fill(terrain, water.seed_cell, water.level)
		for cell: Vector2i in basin.depth_by_cell:
			if basin.depth_by_cell[cell] > WaterBasin.WADE_DEPTH:
				deep[cell] = true
	var footprints: Dictionary = {}
	for feature: MapFeature in _result.features:
		for cell: Vector2i in feature.structure_cells():
			footprints[cell] = true
	var traversable: int = 0
	var buildable: int = 0
	_result.obstructed.resize(_params.alliance_count)
	_result.obstructed.fill(0.0)
	for z: int in terrain.grid_depth():
		for x: int in terrain.grid_width():
			var cell := Vector2i(x, z)
			if not terrain.is_cell_in_play(cell) or footprints.has(cell):
				continue
			if terrain.cell_height_spread(cell) > TerrainGrid.MAX_SLOPE_DIFF or deep.has(cell):
				var share: PackedFloat32Array = MapFavor.access_share(
					Vector2(cell) + Vector2(0.5, 0.5), _result.starts, _params.alliance_count)
				for a: int in share.size():
					_result.obstructed[a] += share[a]
				continue
			traversable += 1
			buildable += 1 if terrain.cell_is_flat(cell) else 0
	var play: float = maxf(_result.play_cell_count, 1)
	_result.traversable_fraction = traversable / play
	_result.buildable_fraction = buildable / play
	if absf(_result.traversable_fraction - _params.target_traversable_fraction) \
			> _params.traversable_tolerance:
		_result.errors.append("%.0f%% of the play area is traversable (target %.0f%% ± %.0f%%)" % [
			100.0 * _result.traversable_fraction, 100.0 * _params.target_traversable_fraction,
			100.0 * _params.traversable_tolerance])
	var total: float = 0.0
	for value: float in _result.obstructed:
		total += value
	var deviation: float = MapFavor.worst_deviation(
		_result.obstructed, total / _params.alliance_count)
	if deviation > _params.obstruction_tolerance:
		_result.errors.append("impassable ground off even by %.0f%% (tolerance %.0f%%)" % [
			deviation * 100.0, _params.obstruction_tolerance * 100.0])


## Every currency's accessible value within tolerance of its even split — the pass 3
## invariant. A miss fails the map; it does not trigger a repair.
func _validate_balance() -> void:
	for currency: int in MapFeature.Currency.values():
		var features: Array[MapFeature] = []
		features.assign(_result.features.filter(
			func(f: MapFeature) -> bool: return f.currency() == currency))
		var accessible: PackedFloat32Array = MapFavor.accessible_value(features, _params.alliance_count)
		var total: float = 0.0
		for value: float in accessible:
			total += value
		var target_each: float = total / float(_params.alliance_count)
		_result.accessible_value[currency] = accessible
		_result.target_value[currency] = target_each
		var deviation: float = MapFavor.worst_deviation(accessible, target_each)
		if deviation > _params.favor_tolerance:
			_result.errors.append("%s balance off by %.0f%% (tolerance %.0f%%)" % [
				MapFeature.Currency.keys()[currency], deviation * 100.0, _params.favor_tolerance * 100.0])
#endregion
