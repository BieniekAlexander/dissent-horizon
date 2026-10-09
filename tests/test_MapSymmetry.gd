extends GutTest

## Tests for MapSymmetry — the generator's training-control mirror
## (gdd/systems/terrain-and-navigation/map-generation.md §Symmetric maps), driven on a
## GeneratedMap built here rather than generated, so each rule is isolated.

## A 20 x 20 diamond play area: a corner grid of 42, so 41 cells and the axis at s = 41.
const _PLAY_SIZE := Vector2i(20, 20)
const _CELLS: int = 41
const _CLEAR_RADIUS_CELLS: int = 3
const _GROUND_HEIGHT: float = 8.0
## The floor of the trench a chasm's water stands in, and that water's level.
const _TRENCH_HEIGHT: float = 2.0
const _WATER_LEVEL: float = 4.0
## Half-width, in corners, of the trench along the diagonal i = j.
const _TRENCH_HALF_WIDTH: int = 2
## The share every kept feature measures, and its swap.
const _MEASURED_SHARE: Array[float] = [0.7, 0.3]


func _map() -> GeneratedMap:
	var map := GeneratedMap.new()
	var terrain := TerrainData.new()
	terrain.play_size = _PLAY_SIZE
	var corners: int = terrain.map_width()
	var heights := PackedFloat32Array()
	heights.resize(corners * corners)
	for j: int in corners:
		for i: int in corners:
			# Asymmetric everywhere, so an unmirrored corner cannot pass by accident.
			heights[j * corners + i] = _GROUND_HEIGHT + 0.01 * i + 0.003 * j
	terrain.heights = heights
	var tiles := PackedByteArray()
	tiles.resize(_CELLS * _CELLS)
	for k: int in tiles.size():
		tiles[k] = k % 3
	terrain.tile_types = tiles
	map.terrain = terrain
	map.starts = [MapStart.at(Vector2(10, 12), 0), MapStart.at(Vector2(30, 28), 1)]
	return map


func _building(origin: Vector2i) -> MapFeature:
	var feature := MapFeature.new()
	feature.kind = MapFeature.Kind.BUILDING_CLUSTER
	var piece: MapPiece = MapPiece.of(&"building", Vector2i(2, 2))
	feature.placements = [{"piece": piece, "origin": origin}]
	feature.center = Vector2(origin) + Vector2.ONE
	feature.value = 1.0
	feature.target_share = PackedFloat32Array([0.6, 0.4])
	feature.realised_share = PackedFloat32Array([0.5, 0.5])
	return feature


func _measured(_point: Vector2) -> PackedFloat32Array:
	return PackedFloat32Array(_MEASURED_SHARE)


func _apply(map: GeneratedMap) -> void:
	MapSymmetry.apply(map, _CLEAR_RADIUS_CELLS, _measured)


func _corner_image(corner: Vector2i) -> Vector2i:
	return Vector2i(_CELLS, _CELLS) - corner


func _cell_image(cell: Vector2i) -> Vector2i:
	return Vector2i(_CELLS - 1, _CELLS - 1) - cell


#region Terrain and starts
func test_heights_and_tiles_are_their_own_images() -> void:
	var map: GeneratedMap = _map()
	_apply(map)
	assert_true(map.errors.is_empty(), str(map.errors))
	var corners: int = _CELLS + 1
	var mismatched: int = 0
	for j: int in corners:
		for i: int in corners:
			var image: Vector2i = _corner_image(Vector2i(i, j))
			if (
				map.terrain.heights[j * corners + i]
				!= map.terrain.heights[image.y * corners + image.x]
			):
				mismatched += 1
	assert_eq(mismatched, 0)
	for z: int in _CELLS:
		for x: int in _CELLS:
			assert_eq(
				map.terrain.tile_at(Vector2i(x, z)),
				map.terrain.tile_at(_cell_image(Vector2i(x, z)))
			)


func test_the_first_starts_half_keeps_its_heights() -> void:
	var map: GeneratedMap = _map()
	var before: PackedFloat32Array = map.terrain.heights.duplicate()
	_apply(map)
	var corners: int = _CELLS + 1
	# Corner (5, 5) lies on the first start's side of the axis, (35, 35) on the other.
	assert_eq(map.terrain.heights[5 * corners + 5], before[5 * corners + 5])
	assert_eq(map.terrain.heights[35 * corners + 35], before[5 * corners + 5])


func test_the_second_start_is_the_first_ones_image() -> void:
	var map: GeneratedMap = _map()
	_apply(map)
	assert_eq(map.starts.size(), 2)
	assert_eq(map.starts[0].position, Vector2(10, 12))
	assert_eq(map.starts[1].position, Vector2(_CELLS, _CELLS) - Vector2(10, 12))
	assert_eq(map.starts[1].alliance, 1)


func test_the_kept_half_is_wherever_the_first_start_is() -> void:
	var map: GeneratedMap = _map()
	map.starts = [MapStart.at(Vector2(30, 28), 0), MapStart.at(Vector2(10, 12), 1)]
	map.features = [_building(Vector2i(30, 25))]
	_apply(map)
	assert_true(map.errors.is_empty(), str(map.errors))
	assert_eq(map.features.size(), 2)
	assert_eq(map.features[0].placements[0].origin, Vector2i(30, 25))


func test_three_starts_are_refused() -> void:
	var map: GeneratedMap = _map()
	map.starts.append(MapStart.at(Vector2(20, 5), 2))
	_apply(map)
	assert_false(map.errors.is_empty())


func test_two_starts_of_one_alliance_are_refused() -> void:
	var map: GeneratedMap = _map()
	map.starts[1].alliance = 0
	_apply(map)
	assert_false(map.errors.is_empty())


func test_a_start_whose_clear_box_crosses_the_axis_is_refused() -> void:
	var map: GeneratedMap = _map()
	# s = 19 + 20 = 39: two short of the axis, inside a three-cell clear radius.
	map.starts = [MapStart.at(Vector2(19, 20), 0), MapStart.at(Vector2(22, 21), 1)]
	_apply(map)
	assert_false(map.errors.is_empty())


#endregion


#region Features
func test_every_kept_feature_has_an_image_and_none_overlap() -> void:
	var map: GeneratedMap = _map()
	map.features = [_building(Vector2i(8, 20)), _building(Vector2i(12, 4))]
	_apply(map)
	assert_eq(map.features.size(), 4)
	for i: int in 2:
		var kept: MapFeature = map.features[i]
		var image: MapFeature = map.features[i + 2]
		assert_eq(image.center, Vector2(_CELLS, _CELLS) - kept.center)
		var image_cells: Array[Vector2i] = image.structure_cells()
		for cell: Vector2i in kept.structure_cells():
			assert_has(image_cells, _cell_image(cell))
	var seen: Dictionary = {}
	for feature: MapFeature in map.features:
		for cell: Vector2i in feature.structure_cells():
			assert_false(seen.has(cell), "two footprints share %s" % cell)
			seen[cell] = true


func test_a_feature_touching_the_axis_is_dropped() -> void:
	var map: GeneratedMap = _map()
	# Cells s = 39..41: the footprint's far corners lie on and past the axis.
	map.features = [_building(Vector2i(19, 20))]
	_apply(map)
	assert_eq(map.features.size(), 0)


func test_a_feature_in_the_other_half_is_dropped() -> void:
	var map: GeneratedMap = _map()
	map.features = [_building(Vector2i(30, 25))]
	_apply(map)
	assert_eq(map.features.size(), 0)


func test_a_pond_whose_rim_reaches_the_axis_is_dropped() -> void:
	var map: GeneratedMap = _map()
	var pond := MapFeature.new()
	pond.kind = MapFeature.Kind.POND
	# s = 37: the pan clears the axis, but its rim's corners reach s = 41.
	pond.pond_cells = [Vector2i(18, 19)]
	pond.target_share = PackedFloat32Array([0.5, 0.5])
	pond.realised_share = PackedFloat32Array([0.5, 0.5])
	map.features = [pond]
	_apply(map)
	assert_eq(map.features.size(), 0)


func test_an_image_takes_its_originals_measured_share_swapped() -> void:
	var map: GeneratedMap = _map()
	map.features = [_building(Vector2i(8, 20))]
	_apply(map)
	assert_eq(map.features[0].realised_share, PackedFloat32Array([0.7, 0.3]))
	assert_eq(map.features[1].realised_share, PackedFloat32Array([0.3, 0.7]))
	assert_eq(map.features[1].target_share, PackedFloat32Array([0.4, 0.6]))
	var accessible: PackedFloat32Array = MapFavor.accessible_value(map.features, 2)
	assert_eq(accessible[0], accessible[1])


#endregion


#region Water
## A trench along the diagonal i = j runs through the centre, so one stretch of water fills it
## from either half.
func _trenched_map() -> GeneratedMap:
	var map: GeneratedMap = _map()
	var corners: int = _CELLS + 1
	var heights: PackedFloat32Array = map.terrain.heights
	for j: int in corners:
		for i: int in corners:
			heights[j * corners + i] = (
				_TRENCH_HEIGHT if absi(i - j) <= _TRENCH_HALF_WIDTH else _GROUND_HEIGHT
			)
	map.terrain.heights = heights
	return map


func test_a_chasm_across_the_axis_stays_one_body() -> void:
	var map: GeneratedMap = _trenched_map()
	map.chasm_waters = [{"seed_cell": Vector2i(15, 15), "level": _WATER_LEVEL}]
	_apply(map)
	assert_eq(map.chasm_waters.size(), 1)
	assert_eq(map.chasm_waters[0].seed_cell, Vector2i(15, 15))


func test_a_chasm_in_the_kept_half_gains_its_image() -> void:
	var map: GeneratedMap = _map()
	var corners: int = _CELLS + 1
	var heights: PackedFloat32Array = map.terrain.heights
	# A pit around cell (12, 14), well clear of the axis.
	for j: int in range(13, 17):
		for i: int in range(11, 15):
			heights[j * corners + i] = _TRENCH_HEIGHT
	map.terrain.heights = heights
	map.chasm_waters = [{"seed_cell": Vector2i(12, 14), "level": _WATER_LEVEL}]
	_apply(map)
	assert_eq(map.chasm_waters.size(), 2)
	assert_eq(map.chasm_waters[1].seed_cell, _cell_image(Vector2i(12, 14)))
	assert_eq(map.chasm_waters[1].level, _WATER_LEVEL)


func test_a_chasm_in_the_other_half_is_dropped() -> void:
	var map: GeneratedMap = _map()
	map.chasm_waters = [{"seed_cell": Vector2i(28, 26), "level": _WATER_LEVEL}]
	_apply(map)
	assert_eq(map.chasm_waters.size(), 0)
#endregion
