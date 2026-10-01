extends GutTest

## Tests for pass 6 of gdd/systems/terrain-and-navigation/map-generation.md: levels from the
## feature graph, cliffs where they meet, ramps, and the guarantees that survive them. Builds
## its own parameters; the defaults are untuned content.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_MapElevation.gd \
##     -gdir=res://tests/none -gexit

## Seeds that generate on these parameters. A seed may legitimately fail an invariant — that is
## a loud rejection, not a bug — so the property tests run on ones known to pass.
const _SEEDS: Array[int] = [2002, 2003, 2004]
## Erosion rounds the corridor measure gives up after; wider than MIN_CHOKE_WIDTH either way.
const _CORRIDOR_LIMIT: int = 12


func _params() -> MapGenerationParams:
	var params: MapGenerationParams = MapGenerationParams.for_start_count(2)
	params.site_piece = MapPiece.of(&"site", Vector2i(2, 2))
	params.shelter_piece = MapPiece.of(&"shelter", Vector2i(3, 3))
	params.building_pool = [MapPiece.of(&"building", Vector2i(4, 4))]
	params.site_energy_per_second = 5.0
	# The pre-2026-10-01 map size and an energy budget scaled to it: these tests check elevation,
	# and a larger map only makes them slower.
	params.play_size_min = 75
	params.play_size_max = 120
	params.energy_value_per_player = 20000.0
	return params


## The same three maps for every test. Generating them is seconds of work each, and every test
## here asks a different question of the SAME maps, so they are built once.
static var _generated: Array[GeneratedMap] = []


func _maps() -> Array[GeneratedMap]:
	if _generated.is_empty():
		for generation_seed: int in _SEEDS:
			_generated.append(MapGenerator.generate(_params(), generation_seed))
	for map: GeneratedMap in _generated:
		assert_true(map.is_valid(), "seed %d: %s" % [map.generation_seed, map.errors])
	return _generated


func test_starts_share_a_level_in_their_band() -> void:
	var params: MapGenerationParams = _params()
	for map: GeneratedMap in _maps():
		var levels: PackedInt32Array = map.elevation.level_of_node
		assert_eq(levels[0], levels[1])
		assert_eq(map.elevation.tier_of_node[0], map.elevation.tier_of_node[1],
			"one start above another is not a fair map")
		var fraction: float = float(levels[0]) / (params.elevation_levels - 1)
		assert_between(fraction, params.start_level_fraction_min, params.start_level_fraction_max)


## Not every seed has relief — a map whose regions all sample the same noise is legitimately
## flat — but a change that flattens EVERY map is the bug this watches for.
func test_the_maps_are_not_all_flat() -> void:
	var heights: Dictionary = {}
	for map: GeneratedMap in _maps():
		for node: int in map.elevation.level_of_node.size():
			heights[map.elevation.node_height(node)] = true
	assert_gt(heights.size(), 1)


## A terrace step is meant to be walked over, so regions the topology left open to each other
## may differ by at most one. Across an uncarved cut the barrier carries any gap.
func test_neighbouring_regions_stay_within_one_terrace() -> void:
	for map: GeneratedMap in _maps():
		var levels: PackedInt32Array = map.elevation.level_of_node
		for edge: Vector2i in map.topology.open_edges():
			assert_lte(absi(levels[edge.x] - levels[edge.y]), 1, "edge %s" % edge)


## The point of the whole pass: elevation marks divisions the topology already made, and adds
## none of its own. Measured as the map sees it — the widest corridor joining the top of the map
## to the bottom must be no narrower once the ground has levels than it was flat.
func test_elevation_does_not_narrow_the_map() -> void:
	var flat_params: MapGenerationParams = _params()
	flat_params.last_pass = MapGenerationParams.Pass.TERRAIN
	for generation_seed: int in _SEEDS:
		var flat: GeneratedMap = MapGenerator.generate(flat_params, generation_seed)
		var levelled: GeneratedMap = MapGenerator.generate(_params(), generation_seed)
		assert_gte(_corridor(levelled), _corridor(flat), "seed %d" % generation_seed)


## How far a corridor can be eroded before the top of the map stops reaching the bottom: a
## stand-in for the narrowest crossing, over walkable ground as the terrain defines it.
func _corridor(a_map: GeneratedMap) -> int:
	var terrain: TerrainData = a_map.terrain
	var width: int = terrain.grid_width()
	var depth: int = terrain.grid_depth()
	var mask := PackedByteArray()
	mask.resize(width * depth)
	for z: int in depth:
		for x: int in width:
			var cell := Vector2i(x, z)
			mask[z * width + x] = 1 if terrain.is_cell_in_play(cell) \
				and terrain.cell_height_spread(cell) <= TerrainGrid.MAX_SLOPE_DIFF else 0
	for eroded: int in range(0, _CORRIDOR_LIMIT):
		var seeds: Array[Vector2i] = []
		for x: int in width:
			for z: int in depth / 8:
				if mask[z * width + x] != 0:
					seeds.append(Vector2i(x, z))
		if seeds.is_empty():
			return eroded
		var field: PathField = PathField.from_seeds(mask, width, depth, seeds)
		var reaches: bool = false
		for x: int in width:
			for z: int in range(depth - depth / 8, depth):
				reaches = reaches or (mask[z * width + x] != 0
					and not is_inf(field.distance(Vector2i(x, z))))
		if not reaches:
			return eroded
		mask = _erode(mask, width, depth)
	return _CORRIDOR_LIMIT


## Drop every walkable cell that touches an unwalkable one.
static func _erode(a_mask: PackedByteArray, a_width: int, a_depth: int) -> PackedByteArray:
	var out: PackedByteArray = a_mask.duplicate()
	for z: int in a_depth:
		for x: int in a_width:
			if a_mask[z * a_width + x] == 0:
				continue
			for dx: int in range(-1, 2):
				for dz: int in range(-1, 2):
					var nx: int = x + dx
					var nz: int = z + dz
					if nx < 0 or nz < 0 or nx >= a_width or nz >= a_depth \
							or a_mask[nz * a_width + nx] == 0:
						out[z * a_width + x] = 0
	return out


func test_footprints_and_start_boxes_stay_level() -> void:
	var params: MapGenerationParams = _params()
	for map: GeneratedMap in _maps():
		for feature: MapFeature in map.features:
			for cell: Vector2i in feature.structure_cells() + feature.pond_cells:
				assert_eq(map.terrain.cell_height_spread(cell), 0.0, "%s" % cell)
		var radius: int = params.start_clear_radius_cells
		for start: MapStart in map.starts:
			var origin := Vector2i((start.position - Vector2(radius, radius)).round())
			for cell: Vector2i in PlacementGrid.rect_cells(origin, Vector2i(radius, radius) * 2):
				assert_eq(map.terrain.cell_height_spread(cell), 0.0, "start box %s" % cell)


func test_a_pond_still_floods_exactly_its_pan() -> void:
	for map: GeneratedMap in _maps():
		for pond: MapFeature in map.features_of(MapFeature.Kind.POND):
			var basin: WaterBasin = WaterBasin.fill(map.terrain, pond.pond_seed_cell, pond.pond_level)
			assert_eq(basin.covered_cells().size(), pond.pond_cells.size())


func test_cliffs_are_steep_and_the_ground_stays_joined() -> void:
	for map: GeneratedMap in _maps():
		for cell: Vector2i in map.elevation.cliff_cells:
			# A ridge or chasm corner can cancel the step — a ridge on a lower level topping out
			# at the upper one. Such a cell is only upper ground beside the barrier: neighbours
			# share edge corners, so it cannot join two levels.
			assert_true(map.terrain.cell_height_spread(cell) > TerrainGrid.MAX_SLOPE_DIFF
				or _touches_barrier(map, cell), "cliff cell %s is walkable" % cell)
		assert_eq(map.elevation._stranded_stretch().size(), 0)


func _touches_barrier(a_map: GeneratedMap, a_cell: Vector2i) -> bool:
	for dx: int in range(-1, 2):
		for dz: int in range(-1, 2):
			if a_map.topology.barrier_of.has(a_cell + Vector2i(dx, dz)):
				return true
	return false


func test_starts_keep_their_routes_across_levels() -> void:
	var params: MapGenerationParams = _params()
	for map: GeneratedMap in _maps():
		var graph: FeatureGraph = map.topology.graph
		assert_gte(graph.disjoint_paths(0, 1, map.elevation.open_edges(map.elevation._ramped),
			params.min_routes), params.min_routes)


func test_no_choke_between_barriers_and_cliffs_is_narrower_than_the_minimum() -> void:
	var width: float = MapGenerationParams.MIN_CHOKE_WIDTH
	for map: GeneratedMap in _maps():
		var play := PlayArea.screen_aligned(
			Vector2(map.terrain.grid_width(), map.terrain.grid_depth()) * 0.5,
			map.terrain.play_half_extents(), Map.CELL_SIZE)
		assert_eq(MapTopology.too_narrow_cells(
			map.topology.barrier_of, play, map.elevation.cliff_cells).size(), 0)


func test_one_level_leaves_the_ground_flat() -> void:
	var params: MapGenerationParams = _params()
	params.elevation_levels = 1
	params.cliff_levels = 1
	var map: GeneratedMap = MapGenerator.generate(params, _SEEDS[0])
	assert_eq(map.elevation.cliff_cells.size(), 0)
	assert_eq(map.elevation.ramp_count, 0)


func test_the_start_level_is_drawn_from_its_band() -> void:
	var params: MapGenerationParams = _params()
	var elevation := MapElevation.new()
	elevation._params = params
	elevation._rng = RandomNumberGenerator.new()
	for _draw: int in 20:
		assert_has([2, 3], elevation.start_level(), "levels 0-4: 0.5 and 0.75 are 2 and 3")
## A ramp's width is the longest UNBROKEN walkable run across it: a slice split in two by an
## obstacle is two narrow corridors, not one wide one. This is what decides whether a ramp is
## too narrow to keep, so it is worth testing away from a generated map.
func test_a_split_ramp_slice_measures_as_its_widest_part() -> void:
	var whole: Dictionary = {}
	for offset: int in range(0, 12):
		whole[offset] = true
	assert_eq(MapElevation._longest_run(whole), 12.0)
	whole.erase(7)
	assert_eq(MapElevation._longest_run(whole), 7.0, "split at 7: runs of 7 and 4")
	assert_eq(MapElevation._longest_run({}), 0.0, "nothing walkable")
	assert_eq(MapElevation._longest_run({5: true, -4: true}), 1.0, "two lone cells")


## A chasm's water must stay in its chasm: the level is measured from the surrounding rim, so a
## chasm lifted onto a high level cannot pour over its cliff and drown the levels below.
func test_chasm_water_stays_in_its_chasm() -> void:
	for map: GeneratedMap in _maps():
		var chasms: Dictionary = {}
		for cell: Vector2i in map.topology.barrier_of:
			if map.topology.flooded[map.topology.barrier_of[cell]]:
				chasms[cell] = true
		for water: Dictionary in map.chasm_waters:
			var basin: WaterBasin = WaterBasin.fill(map.terrain, water.seed_cell, water.level)
			for cell: Vector2i in basin.depth_by_cell:
				# A cell touching the chasm shares its sunk corners, so it may flood too.
				var near_chasm: bool = false
				for dx: int in range(-1, 2):
					for dz: int in range(-1, 2):
						near_chasm = near_chasm or chasms.has(cell + Vector2i(dx, dz))
				assert_true(near_chasm, "water at %s is away from any chasm" % cell)
