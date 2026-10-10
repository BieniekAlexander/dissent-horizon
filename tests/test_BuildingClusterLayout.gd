extends GutTest

## BuildingClusterLayout against synthetic pieces on an open field: the gap and flush rules of
## map-generation.md §Building layout, checked from the geometry it produces.

const SEEDS: int = 40
const SHACK: Vector2i = Vector2i(2, 2)
const LONG: Vector2i = Vector2i(3, 5)
const LARGE: Vector2i = Vector2i(8, 5)


func _pieces(dims: Array[Vector2i]) -> Array[MapPiece]:
	var pieces: Array[MapPiece] = []
	for size: Vector2i in dims:
		pieces.append(MapPiece.of(&"fake_building", size, 1.0, 3))
	return pieces


func _always_free(_origin: Vector2i, _dims: Vector2i) -> bool:
	return true


func _lay_out(rng_seed: int, pieces: Array[MapPiece], params: MapGenerationParams) -> Array[Rect2i]:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var placements: Array[Dictionary] = BuildingClusterLayout.lay_out(
		rng, pieces, Vector2i(100, 100), _always_free, params
	)
	var rects: Array[Rect2i] = []
	for placement: Dictionary in placements:
		rects.append(MapFeature.placement_rect(placement))
	return rects


func test_chebyshev_gap_counts_clear_cells_on_the_wider_axis() -> void:
	var a := Rect2i(0, 0, 2, 2)
	assert_eq(BuildingClusterLayout.chebyshev_gap(a, Rect2i(2, 0, 2, 2)), 0, "edge contact")
	assert_eq(BuildingClusterLayout.chebyshev_gap(a, Rect2i(2, 2, 2, 2)), 0, "corner contact")
	assert_eq(BuildingClusterLayout.chebyshev_gap(a, Rect2i(4, 1, 2, 2)), 2, "facing")
	assert_eq(BuildingClusterLayout.chebyshev_gap(a, Rect2i(5, 3, 2, 2)), 3, "diagonal")
	assert_lt(BuildingClusterLayout.chebyshev_gap(a, Rect2i(1, 1, 2, 2)), 0, "overlap")


func test_flush_needs_facing_footprints_with_a_side_edge_in_line() -> void:
	var a := Rect2i(0, 0, 4, 4)
	assert_true(BuildingClusterLayout.is_flush(a, Rect2i(5, 0, 2, 2)), "top edges in line")
	assert_true(BuildingClusterLayout.is_flush(a, Rect2i(5, 2, 2, 2)), "bottom edges in line")
	assert_false(BuildingClusterLayout.is_flush(a, Rect2i(5, 1, 2, 2)), "staggered")
	assert_false(BuildingClusterLayout.is_flush(a, Rect2i(5, 5, 2, 2)), "diagonal")


func test_partition_never_exceeds_the_largest_grouping() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var pieces: Array[MapPiece] = _pieces([SHACK, SHACK, SHACK, SHACK, SHACK, SHACK, SHACK])
	var weights := PackedFloat32Array([0.0, 0.0, 1.0])
	var groupings: Array[Array] = BuildingClusterLayout.partition(rng, pieces, weights)
	assert_eq(groupings.map(func(g: Array) -> int: return g.size()), [3, 3, 1])


func test_every_pair_is_tight_within_a_grouping_or_open_across_them() -> void:
	var params := MapGenerationParams.new()
	var pieces: Array[MapPiece] = _pieces([LARGE, LONG, SHACK, LONG, SHACK, LARGE, SHACK])
	for rng_seed: int in SEEDS:
		var rects: Array[Rect2i] = _lay_out(rng_seed, pieces, params)
		assert_eq(rects.size(), pieces.size(), "seed %d laid every building out" % rng_seed)
		for i: int in rects.size():
			for j: int in range(i + 1, rects.size()):
				var gap: int = BuildingClusterLayout.chebyshev_gap(rects[i], rects[j])
				assert_gt(gap, 0, "seed %d: %d and %d touch" % [rng_seed, i, j])
				var is_near_miss: bool = (
					gap > params.grouping_gap_cells_max and gap < params.cluster_open_gap_cells_min
				)
				# A near miss may only stand between two members of one grouping, across a third.
				if is_near_miss:
					assert_true(
						_same_grouping(rects, i, j, params),
						"seed %d: %d and %d at gap %d" % [rng_seed, i, j, gap]
					)


func test_no_grouping_is_larger_than_its_weights_allow() -> void:
	var params := MapGenerationParams.new()
	params.grouping_size_weights = PackedFloat32Array([0.0, 1.0])
	var pieces: Array[MapPiece] = _pieces([SHACK, SHACK, SHACK, SHACK, SHACK])
	for rng_seed: int in SEEDS:
		var rects: Array[Rect2i] = _lay_out(rng_seed, pieces, params)
		for i: int in rects.size():
			assert_lte(_grouping(rects, i, params).size(), 2, "seed %d" % rng_seed)


func test_each_grouping_stands_within_the_open_maximum_of_another() -> void:
	var params := MapGenerationParams.new()
	params.grouping_size_weights = PackedFloat32Array([1.0])
	var pieces: Array[MapPiece] = _pieces([LONG, SHACK, LARGE, SHACK])
	for rng_seed: int in SEEDS:
		var rects: Array[Rect2i] = _lay_out(rng_seed, pieces, params)
		for i: int in rects.size():
			var nearest: int = 1 << 30
			for j: int in rects.size():
				if i != j:
					nearest = mini(nearest, BuildingClusterLayout.chebyshev_gap(rects[i], rects[j]))
			assert_between(
				nearest,
				params.cluster_open_gap_cells_min,
				params.cluster_open_gap_cells_max,
				"seed %d building %d" % [rng_seed, i]
			)


func test_a_grouping_beside_a_long_one_stands_across_its_short_axis() -> void:
	var params := MapGenerationParams.new()
	params.grouping_size_weights = PackedFloat32Array([1.0])
	# LARGE is 8 by 5, turned either way, so the shack must go across its short axis, within the
	# span of its long one.
	var pieces: Array[MapPiece] = _pieces([LARGE, SHACK])
	for rng_seed: int in SEEDS:
		var rects: Array[Rect2i] = _lay_out(rng_seed, pieces, params)
		var is_long_in_x: bool = rects[0].size.x > rects[0].size.y
		var is_beside_in_z: bool = (
			rects[1].position.y >= rects[0].end.y or rects[1].end.y <= rects[0].position.y
		)
		assert_eq(
			is_beside_in_z, is_long_in_x, "seed %d: %s beside %s" % [rng_seed, rects[1], rects[0]]
		)
		var merged: Rect2i = rects[0].merge(rects[1])
		var grown: int = (
			merged.size.x - rects[0].size.x if is_long_in_x else merged.size.y - rects[0].size.y
		)
		assert_lte(grown, params.cluster_span_slack_cells, "seed %d" % rng_seed)


func test_a_fixed_footprint_is_built_around_but_not_returned() -> void:
	var params := MapGenerationParams.new()
	var shelter := Rect2i(Vector2i(100, 100), Vector2i(3, 3))
	var pieces: Array[MapPiece] = _pieces([LONG, SHACK, SHACK])
	for rng_seed: int in SEEDS:
		var rng := RandomNumberGenerator.new()
		rng.seed = rng_seed
		var placements: Array[Dictionary] = BuildingClusterLayout.lay_out(
			rng, pieces, Vector2i(0, 0), _always_free, params, [shelter]
		)
		assert_eq(placements.size(), pieces.size(), "seed %d" % rng_seed)
		var nearest: int = 1 << 30
		for placement: Dictionary in placements:
			var rect: Rect2i = MapFeature.placement_rect(placement)
			nearest = mini(nearest, BuildingClusterLayout.chebyshev_gap(rect, shelter))
		assert_between(
			nearest,
			params.cluster_open_gap_cells_min,
			params.cluster_open_gap_cells_max,
			"seed %d: the cluster grew around the shelter" % rng_seed
		)


func test_the_long_sides_of_one_grouping_run_parallel() -> void:
	var params := MapGenerationParams.new()
	params.grouping_size_weights = PackedFloat32Array([0.0, 0.0, 1.0])
	var pieces: Array[MapPiece] = _pieces([LONG, LARGE, SHACK, LARGE, LONG, LONG])
	var axes_seen: Dictionary = {}
	for rng_seed: int in SEEDS:
		var rects: Array[Rect2i] = _lay_out(rng_seed, pieces, params)
		for i: int in rects.size():
			var axes: Dictionary = {}
			for j: int in _grouping(rects, i, params):
				if rects[j].size.x != rects[j].size.y:
					axes[rects[j].size.x > rects[j].size.y] = true
			assert_lte(axes.size(), 1, "seed %d: grouping of %d mixes axes" % [rng_seed, i])
			axes_seen.merge(axes)
	assert_eq(axes_seen.size(), 2, "groupings are laid along both axes across seeds")


func test_grouping_turns_only_turn_what_lies_across() -> void:
	var grouping: Array[MapPiece] = _pieces([LONG, LARGE, SHACK])
	assert_eq(BuildingClusterLayout.grouping_turns(grouping, true), [1, 0, 0] as Array[int])
	assert_eq(BuildingClusterLayout.grouping_turns(grouping, false), [0, 1, 0] as Array[int])


func test_no_room_lays_out_nothing() -> void:
	var rng := RandomNumberGenerator.new()
	var never_free := func(_origin: Vector2i, _dims: Vector2i) -> bool: return false
	var placements: Array[Dictionary] = BuildingClusterLayout.lay_out(
		rng, _pieces([SHACK]), Vector2i.ZERO, never_free, MapGenerationParams.new()
	)
	assert_true(placements.is_empty())


## Buildings reachable from `index` through tight gaps.
func _grouping(rects: Array[Rect2i], index: int, params: MapGenerationParams) -> Array[int]:
	var found: Array[int] = [index]
	var next: int = 0
	while next < found.size():
		for other: int in rects.size():
			if (
				not found.has(other)
				and (
					BuildingClusterLayout.chebyshev_gap(rects[found[next]], rects[other])
					<= params.grouping_gap_cells_max
				)
			):
				found.append(other)
		next += 1
	return found


func _same_grouping(rects: Array[Rect2i], i: int, j: int, params: MapGenerationParams) -> bool:
	return _grouping(rects, i, params).has(j)
