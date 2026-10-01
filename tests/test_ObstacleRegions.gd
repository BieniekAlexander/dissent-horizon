extends GutTest

## Tests for obstacle regions (ObstacleRegions, and their shaping in pass 5): pass 4's cuts grown
## into mountains and lakes until the play area's traversable share falls to its target —
## gdd/systems/terrain-and-navigation/map-generation.md §Obstacle regions.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_ObstacleRegions.gd \
##     -gdir=res://tests/none -gexit
##
## Every test builds its own parameters rather than reading the shipped defaults: the defaults
## are untuned content, and what is under test is the mechanism.

const _SEEDS: Array[int] = [7, 19, 31]


func _params() -> MapGenerationParams:
	var params := MapGenerationParams.new()
	# Passes 1-5: pass 6's cliffs move the share, and have their own tests (test_MapElevation).
	params.last_pass = MapGenerationParams.Pass.TERRAIN
	params.play_size_min = 80
	params.play_size_max = 90
	# A small map keeps these tests fast, so the budgets are scaled to its area.
	params.energy_value_per_player = 13000.0
	params.building_cluster_separation_cells = 10
	params.building_pool = [MapPiece.of(&"building", Vector2i(4, 4), 1.0, 5)]
	params.cut_fraction = 0.45
	return params


func _without_regions(a_params: MapGenerationParams) -> MapGenerationParams:
	a_params.target_traversable_fraction = 1.0
	a_params.traversable_tolerance = 1.0
	a_params.obstruction_tolerance = 1.0
	return a_params


func test_the_same_seed_grows_the_same_regions() -> void:
	var first: GeneratedMap = MapGenerator.generate(_params(), _SEEDS[0])
	var second: GeneratedMap = MapGenerator.generate(_params(), _SEEDS[0])
	assert_eq(first.topology.barrier_of, second.topology.barrier_of)
	assert_eq(first.terrain.heights, second.terrain.heights)


func test_regions_bring_the_traversable_share_to_its_target() -> void:
	for generation_seed: int in _SEEDS:
		var params: MapGenerationParams = _params()
		var map: GeneratedMap = MapGenerator.generate(params, generation_seed)
		assert_true(map.is_valid(), "seed %d: %s" % [generation_seed, map.errors])
		assert_almost_eq(map.traversable_fraction, params.target_traversable_fraction,
			params.traversable_tolerance, "seed %d" % generation_seed)
		var open: GeneratedMap = MapGenerator.generate(_without_regions(_params()), generation_seed)
		assert_gt(open.traversable_fraction, map.traversable_fraction,
			"seed %d: regions take ground" % generation_seed)
		assert_gt(map.topology.grown.count(true), 0, "seed %d" % generation_seed)


func test_no_regions_without_a_target_below_the_open_share() -> void:
	var map: GeneratedMap = MapGenerator.generate(_without_regions(_params()), _SEEDS[0])
	assert_eq(map.topology.grown.count(true), 0)


func test_an_unreachable_target_fails_loudly() -> void:
	var params: MapGenerationParams = _params()
	params.target_traversable_fraction = 0.2
	var map: GeneratedMap = MapGenerator.generate(params, _SEEDS[0])
	assert_false(map.is_valid())
	assert_string_contains(" ".join(map.errors), "traversable")


func test_impassable_ground_is_shared_within_tolerance() -> void:
	for generation_seed: int in _SEEDS:
		var params: MapGenerationParams = _params()
		var map: GeneratedMap = MapGenerator.generate(params, generation_seed)
		var total: float = 0.0
		for value: float in map.obstructed:
			total += value
		assert_lte(MapFavor.worst_deviation(map.obstructed, total / params.alliance_count),
			params.obstruction_tolerance, "seed %d" % generation_seed)


## What growth ADDS keeps clear of every start; a cut's own thin band, drawn before any growth,
## follows the plain barrier rule and may come closer.
func test_regions_keep_clear_of_every_start() -> void:
	var params: MapGenerationParams = _params()
	var clear: float = params.start_clear_radius_cells + params.feature_spacing_cells
	for generation_seed: int in _SEEDS:
		var map: GeneratedMap = MapGenerator.generate(params, generation_seed)
		var plain: GeneratedMap = MapGenerator.generate(_without_regions(_params()), generation_seed)
		for cell: Vector2i in map.topology.barrier_of:
			if not map.topology.grown[map.topology.barrier_of[cell]] \
					or plain.topology.nearest_of.has(cell) \
					and (plain.topology.nearest_of[cell] as Vector3).z <= params.barrier_width_cells:
				continue
			for start: MapStart in map.starts:
				var offset: Vector2 = (Vector2(cell) + Vector2(0.5, 0.5) - start.position).abs()
				assert_gt(maxf(offset.x, offset.y), clear - 1.0,
					"seed %d: %s is inside a start's clearance" % [generation_seed, cell])


func test_the_kind_furthest_below_its_share_grows_next() -> void:
	assert_true(ObstacleRegions.wants_lake(100, 300, 0.5, 0.99), "lakes are behind")
	assert_false(ObstacleRegions.wants_lake(300, 100, 0.5, 0.0), "mountains are behind")
	assert_true(ObstacleRegions.wants_lake(500, 0, 1.0, 0.99), "all lakes stays all lakes")
	assert_false(ObstacleRegions.wants_lake(0, 500, 0.0, 0.0), "all mountains stays so")
	assert_true(ObstacleRegions.wants_lake(0, 0, 0.3, 0.29), "the first is a roll")
	assert_false(ObstacleRegions.wants_lake(0, 0, 0.3, 0.31), "the first is a roll")


func test_a_lake_has_a_wadeable_shelf_and_a_deep_core() -> void:
	var params: MapGenerationParams = _params()
	params.flooded_cut_fraction = 1.0
	var map: GeneratedMap = MapGenerator.generate(params, _SEEDS[0])
	var shallow: int = 0
	var deep: int = 0
	for water: Dictionary in map.chasm_waters:
		var cut: int = map.topology.barrier_of.get(water.seed_cell, -1)
		if cut < 0 or not map.topology.grown[cut]:
			continue
		var basin: WaterBasin = WaterBasin.fill(map.terrain, water.seed_cell, water.level)
		for cell: Vector2i in basin.depth_by_cell:
			if basin.depth_by_cell[cell] > WaterBasin.WADE_DEPTH:
				deep += 1
			elif map.terrain.cell_height_spread(cell) <= TerrainGrid.MAX_SLOPE_DIFF:
				shallow += 1
	assert_gt(deep, 0, "a lake has a deep core")
	assert_gt(shallow, 0, "a lake has shallow water a unit can wade")


func test_a_mountain_rises_above_a_plain_ridge() -> void:
	var params: MapGenerationParams = _params()
	params.flooded_cut_fraction = 0.0
	var map: GeneratedMap = MapGenerator.generate(params, _SEEDS[0])
	var ridge_top: float = params.ground_height + params.ridge_height \
		+ MapGenerationParams.RIDGE_ROUGHNESS
	var peak: float = 0.0
	for height: float in map.terrain.heights:
		peak = maxf(peak, height)
	assert_gt(peak, ridge_top, "some mountain is more than a ridge's edge deep")
	assert_lte(peak, ridge_top + params.mountain_rise_max + 1e-4)
