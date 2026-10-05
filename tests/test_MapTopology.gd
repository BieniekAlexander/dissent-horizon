extends GutTest

## Tests for passes 4 and 5 of gdd/systems/terrain-and-navigation/map-generation.md: the feature
## graph, walking distance, barriers cut and carved, and the terrain they become. Every test
## builds its own parameters; the defaults are untuned content.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_MapTopology.gd \
##     -gdir=res://tests/none -gexit

## Two, because each is a full generation.
const _SEEDS: Array[int] = [5, 17]


func _params() -> MapGenerationParams:
	var params := MapGenerationParams.new()
	# Passes 4-5: pass 6 moves heights, and has its own tests (test_MapElevation).
	params.last_pass = MapGenerationParams.Pass.TERRAIN
	params.play_size_min = Vector2i(80, 80)
	params.play_size_max = Vector2i(90, 90)
	# A small map keeps these tests fast, so the energy budget is scaled to its area.
	params.energy_value_per_player = 13000.0
	params.building_pool = [MapPiece.of(&"building", Vector2i(4, 4), 1.0, 5)]
	params.cut_fraction = 0.4
	# Regions grow (lakes are part of what these tests check), but the shares they aim at are
	# tested in test_ObstacleRegions, not gated here.
	params.traversable_tolerance = 1.0
	params.obstruction_tolerance = 1.0
	return params


## Every test of the default parameters reads the same two maps.
static var _maps: GeneratedMapCache = GeneratedMapCache.new()


func _generate(a_seed: int) -> GeneratedMap:
	return _maps.generated(&"default", _params, a_seed)


#region Feature graph
func test_a_square_triangulates_into_its_sides_and_one_diagonal() -> void:
	var graph: FeatureGraph = FeatureGraph.build(
		PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10), Vector2(0, 11)])
	)
	assert_eq(graph.edges.size(), 5)


func test_disjoint_paths_counts_separate_routes() -> void:
	# A diamond: 0 and 3 joined through 1 and through 2 — two routes sharing no node.
	var graph := FeatureGraph.new()
	graph.positions = PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
	var edges: Array[Vector2i] = [Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 3), Vector2i(2, 3)]
	assert_eq(graph.disjoint_paths(0, 3, edges, 5), 2)
	var through_one: Array[Vector2i] = [
		Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 3), Vector2i(2, 1)
	]
	assert_eq(graph.disjoint_paths(0, 3, through_one, 5), 1, "both routes pass node 1")
	assert_eq(graph.disjoint_paths(0, 3, edges, 1), 1, "counting stops at enough")


#endregion


#region Walking distance
func _open(a_width: int, a_depth: int) -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(a_width * a_depth)
	mask.fill(1)
	return mask


func test_open_ground_distance_is_octile() -> void:
	var seeds: Array[Vector2i] = [Vector2i(0, 0)]
	var field: PathField = PathField.from_seeds(_open(10, 10), 10, 10, seeds)
	assert_almost_eq(field.distance(Vector2i(5, 0)), 5.0, 1e-6)
	assert_almost_eq(field.distance(Vector2i(3, 3)), 4.2, 1e-6)


func test_a_wall_lengthens_the_path_and_a_closed_one_cuts_it() -> void:
	var mask: PackedByteArray = _open(10, 10)
	for z: int in 9:
		mask[z * 10 + 5] = 0  # a wall at x = 5, open only at z = 9
	var seeds: Array[Vector2i] = [Vector2i(0, 0)]
	var around: PathField = PathField.from_seeds(mask, 10, 10, seeds)
	assert_gt(around.distance(Vector2i(9, 0)), 9.0)
	mask[9 * 10 + 5] = 0
	var closed: PathField = PathField.from_seeds(mask, 10, 10, seeds)
	assert_true(is_inf(closed.distance(Vector2i(9, 0))))


#endregion


#region Passes 4 and 5
func test_last_pass_stops_the_generator() -> void:
	var params: MapGenerationParams = _params()
	params.last_pass = MapGenerationParams.Pass.RESOURCES
	var map: GeneratedMap = MapGenerator.generate(params, _SEEDS[0])
	assert_eq(map.passes_run, 3)
	assert_null(map.topology)
	params.last_pass = MapGenerationParams.Pass.EXTENT
	var extent_only: GeneratedMap = MapGenerator.generate(params, _SEEDS[0])
	assert_eq(extent_only.starts.size(), 0)
	assert_eq(extent_only.features.size(), 0)


func test_every_pair_of_starts_keeps_its_routes() -> void:
	var params: MapGenerationParams = _params()
	for generation_seed: int in _SEEDS:
		var map: GeneratedMap = _generate(generation_seed)
		var topology: MapTopology = map.topology
		assert_not_null(topology, str(map.errors))
		assert_gt(topology.cuts.size(), 0)
		assert_gte(
			topology.graph.disjoint_paths(0, 1, topology.open_edges(), params.min_routes),
			params.min_routes,
			"seed %d" % generation_seed
		)


func test_the_walkable_ground_is_one_piece() -> void:
	for generation_seed: int in _SEEDS:
		var topology: MapTopology = _generate(generation_seed).topology
		assert_eq(topology._stranded_cell(), Vector2i(-1, -1), "seed %d" % generation_seed)


func test_every_barrier_cell_is_impassable_terrain() -> void:
	for generation_seed: int in _SEEDS:
		var map: GeneratedMap = _generate(generation_seed)
		var chasms: Dictionary = {}
		for water: Dictionary in map.chasm_waters:
			var basin: WaterBasin = WaterBasin.fill(map.terrain, water.seed_cell, water.level)
			for cell: Vector2i in basin.deep_cells():
				chasms[cell] = true
		# Deep water or too steep: where a chasm meets a ridge, the cells sharing corners with
		# the ridge stand too high to flood, and are steep instead.
		for cell: Vector2i in map.topology.barrier_of:
			var steep: bool = map.terrain.cell_height_spread(cell) > TerrainGrid.MAX_SLOPE_DIFF
			assert_true(
				steep or chasms.has(cell),
				"seed %d: barrier cell %s is walkable" % [generation_seed, cell]
			)


func test_no_barrier_touches_a_feature() -> void:
	for generation_seed: int in _SEEDS:
		var map: GeneratedMap = _generate(generation_seed)
		for feature: MapFeature in map.features:
			for cell: Vector2i in feature.structure_cells() + feature.pond_cells:
				for dx: int in range(-1, 2):
					for dz: int in range(-1, 2):
						assert_false(
							map.topology.barrier_of.has(cell + Vector2i(dx, dz)),
							"seed %d: barrier next to %s" % [generation_seed, cell]
						)


func test_no_cuts_leaves_the_ground_flat() -> void:
	var params: MapGenerationParams = _params()
	params.cut_fraction = 0.0
	var map: GeneratedMap = MapGenerator.generate(params, _SEEDS[0])
	assert_eq(map.topology.barrier_of.size(), 0)
	assert_eq(map.chasm_waters.size(), 0)


func test_all_flooded_cuts_make_chasm_water_and_no_ridges() -> void:
	var params: MapGenerationParams = _params()
	params.flooded_cut_fraction = 1.0
	var map: GeneratedMap = MapGenerator.generate(params, _SEEDS[0])
	assert_gt(map.chasm_waters.size(), 0)
	var peak: float = params.ground_height
	for height: float in map.terrain.heights:
		peak = maxf(peak, height)
	assert_eq(peak, params.ground_height, "a ridge was raised")


## A chasm's water must stay in its chasm: the level is measured from the surrounding rim, so a
## chasm lifted onto a high level cannot pour over its cliff and drown the levels below. A lake
## also floods its shelf, lake_shelf_cells wide.
func test_chasm_water_stays_in_its_chasm() -> void:
	var params: MapGenerationParams = _params()
	for map: GeneratedMap in [MapGenerator.generate(params, _SEEDS[0])]:
		var reach_of: Dictionary = {}
		for cell: Vector2i in map.topology.barrier_of:
			var cut: int = map.topology.barrier_of[cell]
			if map.topology.flooded[cut]:
				reach_of[cell] = 1 + (params.lake_shelf_cells if map.topology.grown[cut] else 0)
		for water: Dictionary in map.chasm_waters:
			var basin: WaterBasin = WaterBasin.fill(map.terrain, water.seed_cell, water.level)
			for cell: Vector2i in basin.depth_by_cell:
				# A cell touching the chasm shares its sunk corners, so it may flood too.
				var near_chasm: bool = false
				var reach: int = 1 + params.lake_shelf_cells
				for dx: int in range(-reach, reach + 1):
					for dz: int in range(-reach, reach + 1):
						var chasm: Vector2i = cell + Vector2i(dx, dz)
						near_chasm = (
							near_chasm
							or (reach_of.has(chasm) and maxi(absi(dx), absi(dz)) <= reach_of[chasm])
						)
				assert_true(near_chasm, "water at %s is away from any chasm" % cell)


#endregion


#region Choke width
func test_gap_arithmetic() -> void:
	# Three apart: the two cells between are both steep borders.
	assert_almost_eq(MapTopology.walkable_gap(Vector2i(0, 0), Vector2i(3, 0)), 0.0, 1e-6)
	assert_almost_eq(MapTopology.walkable_gap(Vector2i(0, 0), Vector2i(13, 0)), 10.0, 1e-6)


func test_barriers_too_close_are_trimmed_from_the_smaller() -> void:
	var play := PlayArea.axis_aligned(Vector2(50, 50), Vector2(50, 50))
	var cells: Dictionary = {}
	for z: int in range(40, 60):
		cells[Vector2i(40, z)] = 0  # a long wall
	for z: int in range(48, 51):
		cells[Vector2i(45, z)] = 1  # a short stub five cells from it
	var doomed: Dictionary = MapTopology.too_narrow_cells(cells, play)
	assert_true(doomed.has(Vector2i(45, 49)), "the stub goes")
	assert_false(doomed.has(Vector2i(40, 49)), "the wall stays")


func test_barriers_are_trimmed_to_the_width_asked_for() -> void:
	var play := PlayArea.axis_aligned(Vector2(50, 50), Vector2(50, 50))
	var cells: Dictionary = {}
	for z: int in range(35, 65):
		cells[Vector2i(40, z)] = 0  # a long wall
	for z: int in range(48, 51):
		cells[Vector2i(58, z)] = 1  # a short stub fifteen walkable cells from it
	assert_false(MapTopology.too_narrow_cells(cells, play).has(Vector2i(58, 49)), "the floor")
	assert_true(
		MapTopology.too_narrow_cells(cells, play, {}, 20.0).has(Vector2i(58, 49)),
		"a twenty-cell gap"
	)


## A cliff follows a barrier rather than standing as a mass of its own, so a barrier keeps only
## the floor from one, whatever width barriers keep from each other.
func test_a_cliff_is_held_only_to_the_floor() -> void:
	var play := PlayArea.axis_aligned(Vector2(50, 50), Vector2(50, 50))
	var cliffs: Dictionary = {}
	for z: int in range(35, 65):
		cliffs[Vector2i(40, z)] = true
	var near: Dictionary = {Vector2i(46, 50): 0}
	var far: Dictionary = {Vector2i(56, 50): 0}
	assert_true(MapTopology.too_narrow_cells(near, play, cliffs, 20.0).has(Vector2i(46, 50)))
	assert_false(MapTopology.too_narrow_cells(far, play, cliffs, 20.0).has(Vector2i(56, 50)))


func test_a_barrier_touching_the_play_edge_is_kept() -> void:
	var play := PlayArea.axis_aligned(Vector2(50, 50), Vector2(50, 50))
	var cells: Dictionary = {}
	for x: int in range(1, 12):
		cells[Vector2i(x, 50)] = 0  # runs from the edge inward
	assert_true(MapTopology.too_narrow_cells(cells, play, {}, 20.0).is_empty())


func test_a_barrier_near_the_play_edge_is_trimmed() -> void:
	var play := PlayArea.axis_aligned(Vector2(50, 50), Vector2(50, 50))
	var cells: Dictionary = {Vector2i(5, 50): 0, Vector2i(30, 50): 0}
	var doomed: Dictionary = MapTopology.too_narrow_cells(cells, play)
	assert_true(doomed.has(Vector2i(5, 50)))
	assert_false(doomed.has(Vector2i(30, 50)))


## Independent of the trimmer: every pair of cells from different obstacles leaves at least
## open_gap_cells walkable, and so does every cell and the play edge, unless its obstacle
## touches the edge — closed, not narrowed.
func test_no_generated_gap_is_narrower_than_the_open_gap() -> void:
	var width: float = _params().open_gap_cells
	for generation_seed: int in _SEEDS:
		var map: GeneratedMap = _generate(generation_seed)
		var cells: Dictionary = map.topology.barrier_of
		var play := PlayArea.screen_aligned(
			Vector2(map.terrain.grid_width(), map.terrain.grid_depth()) * 0.5,
			map.terrain.play_half_extents(),
			Map.CELL_SIZE
		)
		var obstacle_of: Dictionary = MapTopology.obstacles(cells)
		var touching: Dictionary = {}
		for cell: Vector2i in cells:
			if MapTopology.edge_gap(cell, play) < MapTopology.EDGE_TOUCH_GAP:
				touching[obstacle_of[cell]] = true
		# Collected and asserted once: one GUT assert per pair of cells is most of this test's time.
		var narrow: Array[String] = []
		var keys: Array = cells.keys()
		for i: int in keys.size():
			if (
				not touching.has(obstacle_of[keys[i]])
				and MapTopology.edge_gap(keys[i], play) < width
			):
				narrow.append("%s near the edge" % keys[i])
			for j: int in range(i + 1, keys.size()):
				if (
					obstacle_of[keys[i]] != obstacle_of[keys[j]]
					and MapTopology.walkable_gap(keys[i], keys[j]) < width
				):
					narrow.append("%s and %s" % [keys[i], keys[j]])
		assert_eq(narrow, [] as Array[String], "seed %d" % generation_seed)
#endregion
