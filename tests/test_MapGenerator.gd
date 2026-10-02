extends GutTest

## Tests for MapGenerator — passes 1-3 of gdd/systems/terrain-and-navigation/map-generation.md
## over flat ground: the start ring, favor-steered placement, pond pans and the balance check.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_MapGenerator.gd \
##     -gdir=res://tests/none -gexit
##
## Every test builds its own parameters rather than reading the shipped defaults: the defaults
## are untuned content, and what is under test is the mechanism.

## Seeds each property is checked across. A handful, because each is a full generation.
const _SEEDS: Array[int] = [11, 23, 37, 41, 59]


func _params() -> MapGenerationParams:
	var params := MapGenerationParams.new()
	# Passes 1-5: pass 6 moves heights, and has its own tests (test_MapElevation).
	params.last_pass = MapGenerationParams.Pass.TERRAIN
	params.play_size_min = Vector2i(75, 75)
	params.play_size_max = Vector2i(90, 90)
	# A small map keeps these tests fast, so the energy budget is scaled to its area (about a
	# third of a shipped 1v1 map's). The tests check the mechanics, not the shipped amounts.
	params.energy_value_per_player = 13000.0
	# Likewise the building clusters' separation: at the shipped 20 cells a map this small runs
	# out of room for the clusters.
	params.building_cluster_separation_cells = 10
	# Obstacle regions are tested in test_ObstacleRegions: off here, and their checks with them.
	params.target_traversable_fraction = 1.0
	params.traversable_tolerance = 1.0
	params.obstruction_tolerance = 1.0
	params.building_pool = [
		MapPiece.of(&"small_building", Vector2i(2, 2), 3.0, 3),
		MapPiece.of(&"large_building", Vector2i(3, 3), 1.0, 6),
	]
	return params


func _generate(a_seed: int) -> GeneratedMap:
	return MapGenerator.generate(_params(), a_seed)


#region Determinism
func test_the_same_seed_makes_the_same_map() -> void:
	var first: GeneratedMap = _generate(_SEEDS[0])
	var second: GeneratedMap = _generate(_SEEDS[0])
	assert_eq(first.features.size(), second.features.size())
	for i: int in first.features.size():
		assert_eq(first.features[i].center, second.features[i].center)
	for i: int in first.starts.size():
		assert_eq(first.starts[i].position, second.starts[i].position)
	assert_eq(first.terrain.heights, second.terrain.heights)


#endregion


#region Starts
func test_starts_are_separated_and_inside_the_margin() -> void:
	for generation_seed: int in _SEEDS:
		var map: GeneratedMap = _generate(generation_seed)
		assert_true(map.is_valid(), "seed %d: %s" % [generation_seed, map.errors])
		var params: MapGenerationParams = _params()
		assert_eq(map.starts.size(), params.start_count())
		var area := PlayArea.screen_aligned(
			Vector2(map.terrain.grid_width(), map.terrain.grid_depth()) * 0.5,
			map.terrain.play_half_extents(),
			Map.CELL_SIZE
		)
		var separation: float = params.start_separation_diagonal_fraction * area.diagonal()
		assert_gte(map.starts[0].position.distance_to(map.starts[1].position), separation)
		for start: MapStart in map.starts:
			var local: Vector2 = area.to_local(start.position)
			assert_lte(absf(local.x), area.half.x - params.start_edge_margin_cells)
			assert_lte(absf(local.y), area.half.y - params.start_edge_margin_cells)
			# The least distance from the centre, less the whole-cell snap.
			assert_gte((local / area.half).length(), 2.0 * params.start_min_center_fraction - 0.02)


func test_play_size_is_drawn_within_its_bounds() -> void:
	var params: MapGenerationParams = _params()
	for generation_seed: int in _SEEDS:
		var size: Vector2i = _generate(generation_seed).play_size
		assert_between(size.x, params.play_size_min.x, params.play_size_max.x)
		assert_between(size.y, params.play_size_min.y, params.play_size_max.y)


## Each axis has its own range, so a long map can be asked for.
func test_each_axis_is_drawn_within_its_own_bounds() -> void:
	var params: MapGenerationParams = _params()
	params.play_size_min = Vector2i(70, 90)
	params.play_size_max = Vector2i(70, 90)
	assert_eq(MapGenerator.generate(params, _SEEDS[0]).play_size, Vector2i(70, 90))


func test_start_count_defaults_come_from_the_table() -> void:
	var bounds: Array = MapGenerationParams.PLAY_SIZE_RANGE_BY_START_COUNT[2]
	var params: MapGenerationParams = MapGenerationParams.for_start_count(2)
	assert_eq(params.play_size_min, bounds[0])
	assert_eq(params.play_size_max, bounds[1])


func test_one_start_per_alliance_in_a_two_alliance_map() -> void:
	var map: GeneratedMap = _generate(_SEEDS[0])
	assert_eq(map.starts[0].alliance, 0)
	assert_eq(map.starts[1].alliance, 1)


func test_nothing_is_placed_in_a_start_clear_box() -> void:
	var params: MapGenerationParams = _params()
	var half: float = params.start_clear_radius_cells
	for generation_seed: int in _SEEDS:
		var map: GeneratedMap = _generate(generation_seed)
		for feature: MapFeature in map.features:
			var cells: Array[Vector2i] = feature.structure_cells() + feature.pond_cells
			for cell: Vector2i in cells:
				for start: MapStart in map.starts:
					var offset: Vector2 = (Vector2(cell) + Vector2(0.5, 0.5) - start.position).abs()
					assert_false(
						offset.x < half and offset.y < half,
						"seed %d: %s inside a start square" % [generation_seed, cell]
					)


func test_a_start_clear_box_is_flat_and_the_radius_wide() -> void:
	var params: MapGenerationParams = _params()
	params.start_clear_radius_cells = 10
	for generation_seed: int in _SEEDS:
		var map: GeneratedMap = MapGenerator.generate(params, generation_seed)
		# Terrain is final once pass 5 ran; a balance miss afterwards does not unshape it.
		assert_eq(map.passes_run, params.last_pass, str(map.errors))
		for start: MapStart in map.starts:
			var origin := Vector2i((start.position - Vector2(10, 10)).round())
			# A 20x20 box of cells, all in play and flat at ground height.
			for cell: Vector2i in PlacementGrid.rect_cells(origin, Vector2i(20, 20)):
				assert_true(map.terrain.is_cell_in_play(cell))
				assert_eq(map.terrain.cell_height_spread(cell), 0.0)
				assert_eq(map.terrain.cell_mean_height(cell), params.ground_height)


#endregion


#region Placement
func test_structures_are_in_play_and_never_touch() -> void:
	for generation_seed: int in _SEEDS:
		var map: GeneratedMap = _generate(generation_seed)
		var owner_of: Dictionary = {}
		for i: int in map.features.size():
			for cell: Vector2i in map.features[i].structure_cells() + map.features[i].pond_cells:
				assert_true(
					map.terrain.is_cell_in_play(cell),
					"seed %d: %s out of play" % [generation_seed, cell]
				)
				assert_false(
					owner_of.has(cell), "seed %d: %s claimed twice" % [generation_seed, cell]
				)
				owner_of[cell] = i
		# The footprint gap: no cell of one feature is 8-adjacent to a cell of another.
		for cell: Vector2i in owner_of:
			for dx: int in range(-1, 2):
				for dz: int in range(-1, 2):
					var neighbour: Vector2i = cell + Vector2i(dx, dz)
					if owner_of.has(neighbour):
						assert_eq(
							owner_of[neighbour],
							owner_of[cell],
							"seed %d: features touch at %s" % [generation_seed, cell]
						)


func test_every_currency_is_balanced_within_tolerance() -> void:
	var params: MapGenerationParams = _params()
	for generation_seed: int in _SEEDS:
		var map: GeneratedMap = _generate(generation_seed)
		for currency: int in MapFeature.Currency.values():
			var accessible: PackedFloat32Array = map.accessible_value[currency]
			assert_lte(
				MapFavor.worst_deviation(accessible, map.target_value[currency]),
				params.favor_tolerance,
				"seed %d currency %d" % [generation_seed, currency]
			)


func test_shelter_count_follows_alliance_count() -> void:
	for generation_seed: int in _SEEDS:
		var count: int = _generate(generation_seed).features_of(MapFeature.Kind.SHELTER).size()
		assert_between(count, 2, 5)


func test_building_capacity_is_the_per_player_budget() -> void:
	var params: MapGenerationParams = _params()
	var largest: int = 0
	for piece: MapPiece in params.building_pool:
		largest = maxi(largest, piece.capacity)
	var budget: int = params.building_capacity_per_player * params.start_count()
	for generation_seed: int in _SEEDS:
		var capacity: float = 0.0
		var map: GeneratedMap = _generate(generation_seed)
		for cluster: MapFeature in map.features_of(MapFeature.Kind.BUILDING_CLUSTER):
			capacity += cluster.value
		assert_gte(capacity, budget)
		assert_lt(capacity, budget + largest)


func test_clusters_keep_their_separation() -> void:
	var params: MapGenerationParams = _params()
	var separation: Dictionary = {
		MapFeature.Kind.BUILDING_CLUSTER: params.building_cluster_separation_cells,
		MapFeature.Kind.SITE_CLUSTER: params.site_cluster_separation_cells,
	}
	for generation_seed: int in _SEEDS:
		var map: GeneratedMap = _generate(generation_seed)
		for kind: MapFeature.Kind in separation:
			var clusters: Array[MapFeature] = map.features_of(kind)
			for i: int in clusters.size():
				for j: int in range(i + 1, clusters.size()):
					assert_gte(
						_nearest(clusters[i], clusters[j]),
						separation[kind],
						"seed %d kind %d: clusters %d and %d" % [generation_seed, kind, i, j]
					)


## L1 distance between the nearest members of two clusters.
func _nearest(a_cluster: MapFeature, a_other: MapFeature) -> int:
	var nearest: int = 1 << 30
	for a: Dictionary in a_cluster.placements:
		for b: Dictionary in a_other.placements:
			nearest = mini(
				nearest,
				FeaturePlacer.footprint_l1_distance(
					Rect2i(a.origin, (a.piece as MapPiece).footprint),
					Rect2i(b.origin, (b.piece as MapPiece).footprint)
				)
			)
	return nearest


## A pool of very different footprints — a shack, a long piece, a wide one — as a neutral-building
## family produces. Fixture pieces, not the authored ones: what is under test is that placement
## does not assume a square, a small footprint or a single size.
func _mixed_pool_params() -> MapGenerationParams:
	var params: MapGenerationParams = _params()
	params.building_pool = [
		MapPiece.of(&"shack", Vector2i(2, 2), 1.0, 3),
		MapPiece.of(&"square", Vector2i(4, 4), 1.0, 5),
		MapPiece.of(&"long", Vector2i(3, 5), 1.0, 5),
		MapPiece.of(&"wide", Vector2i(8, 5), 1.0, 10),
	]
	return params


func test_a_mixed_pool_of_non_square_pieces_generates_a_valid_map() -> void:
	var params: MapGenerationParams = _mixed_pool_params()
	var drawn: Dictionary = {}
	for generation_seed: int in _SEEDS:
		var map: GeneratedMap = MapGenerator.generate(params, generation_seed)
		assert_true(map.is_valid(), "seed %d: %s" % [generation_seed, map.errors])
		var claimed: Dictionary = {}
		for cluster: MapFeature in map.features_of(MapFeature.Kind.BUILDING_CLUSTER):
			for placement: Dictionary in cluster.placements:
				var piece: MapPiece = placement.piece
				drawn[piece.id] = true
				# The whole footprint, in its authored orientation, is in play and unshared.
				for cell: Vector2i in PlacementGrid.rect_cells(placement.origin, piece.footprint):
					assert_true(
						map.terrain.is_cell_in_play(cell),
						"seed %d: %s %s out of play" % [generation_seed, piece.id, cell]
					)
					assert_false(
						claimed.has(cell), "seed %d: %s claimed twice" % [generation_seed, cell]
					)
					claimed[cell] = true
	for piece: MapPiece in params.building_pool:
		assert_true(drawn.has(piece.id), "%s is drawn across the seeds" % piece.id)


func test_a_mixed_pool_keeps_cluster_separation_and_the_building_budget() -> void:
	var params: MapGenerationParams = _mixed_pool_params()
	var largest: int = 0
	for piece: MapPiece in params.building_pool:
		largest = maxi(largest, piece.capacity)
	for generation_seed: int in _SEEDS:
		var map: GeneratedMap = MapGenerator.generate(params, generation_seed)
		var clusters: Array[MapFeature] = map.features_of(MapFeature.Kind.BUILDING_CLUSTER)
		var capacity: float = 0.0
		for cluster: MapFeature in clusters:
			capacity += cluster.value
		var budget: int = params.building_capacity_per_player * params.start_count()
		assert_gte(capacity, budget)
		assert_lt(capacity, budget + largest)
		for i: int in clusters.size():
			for j: int in range(i + 1, clusters.size()):
				assert_gte(
					_nearest(clusters[i], clusters[j]),
					params.building_cluster_separation_cells,
					"seed %d: clusters %d and %d" % [generation_seed, i, j]
				)


func test_a_building_cluster_is_sized_by_capacity_not_count() -> void:
	var params: MapGenerationParams = _mixed_pool_params()
	var edges: PackedInt32Array = params.cluster_capacity_band_edges
	var top: int = edges[edges.size() - 1] + params.cluster_capacity_overshoot
	for generation_seed: int in _SEEDS:
		var map: GeneratedMap = MapGenerator.generate(params, generation_seed)
		var clusters: Array[MapFeature] = map.features_of(MapFeature.Kind.BUILDING_CLUSTER)
		# The last cluster may be cut short at the budget, so only the ceiling holds for all.
		for cluster: MapFeature in clusters:
			var capacity: int = 0
			for placement: Dictionary in cluster.placements:
				capacity += (placement.piece as MapPiece).capacity
			assert_eq(float(capacity), cluster.value, "a cluster's value is its capacity")
			assert_lte(capacity, top, "seed %d" % generation_seed)


func test_cluster_capacity_bands_hold_in_expectation() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var edges := PackedInt32Array([3, 10, 15, 20, 25])
	var weights := PackedFloat32Array([0.55, 0.36, 0.07, 0.02])
	var counts: Array[int] = [0, 0, 0, 0]
	var draws: int = 20000
	for _i: int in draws:
		var capacity: float = MapGenerator.cluster_capacity(rng, edges, weights)
		assert_between(capacity, float(edges[0]), float(edges[4]))
		counts[clampi(edges.bsearch(int(capacity), false) - 1, 0, 3)] += 1
	for band: int in weights.size():
		assert_almost_eq(counts[band] / float(draws), weights[band], 0.015, "band %d" % band)


func test_a_larger_cluster_leans_toward_larger_buildings() -> void:
	var pool: Array[MapPiece] = [
		MapPiece.of(&"small", Vector2i(2, 2), 1.0, 3), MapPiece.of(&"big", Vector2i(8, 5), 1.0, 10)
	]
	var edges := PackedInt32Array([3, 10, 15, 20, 25])
	var smallest: PackedFloat32Array = MapGenerator.building_weights(pool, edges, 0.5, 3.0)
	var largest: PackedFloat32Array = MapGenerator.building_weights(pool, edges, 0.5, 25.0)
	assert_almost_eq(
		smallest[1] / smallest[0], 1.0, 0.001, "the smallest cluster keeps the pool's weights"
	)
	assert_gt(largest[1] / largest[0], 1.0, "the largest cluster favours the big building")
	var flat: PackedFloat32Array = MapGenerator.building_weights(pool, edges, 0.0, 25.0)
	assert_almost_eq(flat[1] / flat[0], 1.0, 0.001, "no bias, no lean")


func test_a_site_cluster_is_one_to_three_sites_edge_to_edge() -> void:
	for generation_seed: int in _SEEDS:
		for cluster: MapFeature in _generate(generation_seed).features_of(
			MapFeature.Kind.SITE_CLUSTER
		):
			var rects: Array[Rect2i] = []
			for placement: Dictionary in cluster.placements:
				rects.append(Rect2i(placement.origin, (placement.piece as MapPiece).footprint))
			assert_between(rects.size(), 1, 3)
			# Every member shares an edge with another: L1 1, and flush (same row or column).
			for i: int in rects.size():
				if rects.size() == 1:
					continue
				var touches: bool = false
				for j: int in rects.size():
					if (
						i != j
						and FeaturePlacer.footprint_l1_distance(rects[i], rects[j]) == 1
						and (
							rects[i].position.x == rects[j].position.x
							or rects[i].position.y == rects[j].position.y
						)
					):
						touches = true
				assert_true(
					touches, "seed %d: a site stands apart from its cluster" % generation_seed
				)


func test_site_cluster_sizes_partition_the_site_count() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for site_count: int in [0, 1, 2, 5, 10, 17]:
		for _draw: int in 20:
			var sizes: Array[int] = MapGenerator.site_cluster_sizes(rng, site_count, 0.3, 0.3)
			assert_eq(sizes.reduce(func(t: int, n: int) -> int: return t + n, 0), site_count)
			for size: int in sizes:
				assert_between(size, 1, 3)
	assert_eq(MapGenerator.site_cluster_sizes(rng, 6, 1.0, 1.0), [3, 3] as Array[int])


func test_site_cluster_fractions_hold_in_expectation() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var draws: int = 2000
	var in_threes: int = 0
	var in_twos: int = 0
	for _draw: int in draws:
		for size: int in MapGenerator.site_cluster_sizes(rng, 5, 0.3, 0.2):
			in_threes += 3 if size == 3 else 0
			in_twos += 2 if size == 2 else 0
	# Five sites: 1.5 sites expected in threes (0.5 of a three) and 1.0 in twos (0.5 of a two).
	assert_almost_eq(float(in_threes) / draws, 1.5, 0.15)
	assert_almost_eq(float(in_twos) / draws, 1.0, 0.15)


func test_footprint_l1_distance() -> void:
	var a := Rect2i(Vector2i(0, 0), Vector2i(2, 2))
	assert_eq(FeaturePlacer.footprint_l1_distance(a, Rect2i(Vector2i(1, 1), Vector2i(2, 2))), 0)
	assert_eq(FeaturePlacer.footprint_l1_distance(a, Rect2i(Vector2i(2, 0), Vector2i(2, 2))), 1)
	assert_eq(FeaturePlacer.footprint_l1_distance(a, Rect2i(Vector2i(2, 2), Vector2i(2, 2))), 2)
	assert_eq(FeaturePlacer.footprint_l1_distance(a, Rect2i(Vector2i(5, 4), Vector2i(1, 1))), 7)


func test_no_buildings_without_a_pool() -> void:
	var params: MapGenerationParams = _params()
	params.building_pool = []
	var map: GeneratedMap = MapGenerator.generate(params, _SEEDS[0])
	assert_true(map.is_valid(), str(map.errors))
	assert_eq(map.features_of(MapFeature.Kind.BUILDING_CLUSTER).size(), 0)


func test_an_impossible_map_fails_loudly() -> void:
	var params: MapGenerationParams = _params()
	params.play_size_min = Vector2i(12, 12)
	params.play_size_max = Vector2i(12, 12)
	var map: GeneratedMap = MapGenerator.generate(params, _SEEDS[0])
	assert_false(map.is_valid())
	assert_gt(map.errors.size(), 0)


func test_a_map_with_no_energy_budget_fails_loudly() -> void:
	var params: MapGenerationParams = _params()
	params.energy_value_per_player = 0.0
	assert_gt(params.warnings().size(), 0, "the form warns before generating")
	var map: GeneratedMap = MapGenerator.generate(params, _SEEDS[0])
	assert_false(map.is_valid(), "a map with no ponds or sites is not a valid map")
	assert_eq(map.features_of(MapFeature.Kind.POND).size(), 0)
	assert_eq(map.features_of(MapFeature.Kind.SITE_CLUSTER).size(), 0)


func test_a_positive_energy_budget_places_ponds_and_sites() -> void:
	for generation_seed: int in _SEEDS:
		var map: GeneratedMap = _generate(generation_seed)
		assert_true(map.is_valid(), "seed %d: %s" % [generation_seed, map.errors])
		assert_gt(map.features_of(MapFeature.Kind.POND).size(), 0, "seed %d" % generation_seed)
		assert_gt(
			map.features_of(MapFeature.Kind.SITE_CLUSTER).size(), 0, "seed %d" % generation_seed
		)


#endregion


#region Ponds
func test_a_pond_floods_exactly_its_pan_and_is_wadeable() -> void:
	for generation_seed: int in _SEEDS:
		var map: GeneratedMap = _generate(generation_seed)
		for pond: MapFeature in map.features_of(MapFeature.Kind.POND):
			var basin: WaterBasin = WaterBasin.fill(
				map.terrain, pond.pond_seed_cell, pond.pond_level
			)
			var flooded: Array[Vector2i] = basin.covered_cells()
			assert_eq(flooded.size(), pond.pond_cells.size(), "seed %d" % generation_seed)
			for cell: Vector2i in pond.pond_cells:
				assert_true(
					basin.is_shallow(cell), "seed %d: %s not shallow" % [generation_seed, cell]
				)


func test_a_pond_rim_is_walkable_but_not_flat() -> void:
	var map: GeneratedMap = _generate(_SEEDS[0])
	var ponds: Array[MapFeature] = map.features_of(MapFeature.Kind.POND)
	assert_gt(ponds.size(), 0)
	var pan: Dictionary = {}
	for cell: Vector2i in ponds[0].pond_cells:
		pan[cell] = true
	for cell: Vector2i in ponds[0].pond_cells:
		for dx: int in range(-1, 2):
			for dz: int in range(-1, 2):
				var rim: Vector2i = cell + Vector2i(dx, dz)
				if pan.has(rim):
					continue
				assert_almost_eq(map.terrain.cell_height_spread(rim), FeaturePlacer.POND_SINK, 1e-5)


## Cells times richness, capped at the charge bound: filling the pan's holes can grow a pond a
## few cells past its planned size, and the bound is a design promise.
func test_pond_charge_is_cells_times_richness_within_the_bound() -> void:
	var params: MapGenerationParams = _params()
	for generation_seed: int in _SEEDS:
		for pond: MapFeature in _generate(generation_seed).features_of(MapFeature.Kind.POND):
			assert_has(params.pond_richness_factors, pond.pond_richness)
			assert_eq(
				pond.pond_charge,
				mini(pond.pond_cells.size() * pond.pond_richness, params.pond_charge_max)
			)
			assert_lte(pond.pond_charge, params.pond_charge_max)
			assert_gte(pond.pond_cells.size(), params.pond_cells_min)
#endregion
