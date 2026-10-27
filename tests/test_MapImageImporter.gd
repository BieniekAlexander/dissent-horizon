extends GutTest

## The map image importer's pure core (map-from-image.md §Testing): palette classification and
## the frame, levels and smoothing, cliffs and ramps, chasms, water levels and seeds, structure
## segmentation and matching, edge noise and the re-import flags. Every drawing is a small
## synthetic one built here, never a shipped map or a shipped piece: structures are matched
## against fake footprints, so a retuned shelter cannot fail this file.

## 12 x 12 diamonds: a 25 x 25 cell grid, the drawing's pixels one to one.
const _PLAY := Vector2i(12, 12)
const _MIDDLE: int = 12
const _SHELTER := Vector2i(3, 3)
## Out-of-play pixels framing a drawing, so a marked pixel's position is checked off the canvas.
const _MARGIN: int = 2
const _LONG := Vector2i(3, 5)
const _SQUARE := Vector2i(4, 4)
## A level step a walker climbs sheer, under TerrainGrid.MAX_SLOPE_DIFF.
const _WALKABLE_STEP: float = 0.5

var _params: MapImageImportParams


func before_each() -> void:
	_params = MapImageImportParams.new()
	_params.edge_noise_cells = 0.0
	_params.smoothing_radius = 0
	_params.generation.shelter_piece = MapPiece.of(&"fake_shelter", _SHELTER)
	_params.generation.building_pool.assign(
		[MapPiece.of(&"fake_long", _LONG), MapPiece.of(&"fake_square", _SQUARE)]
	)


#region Drawing helpers
## A drawing of `_PLAY` in play, every cell `a_level`, beyond it the out-of-play colour, framed
## by `a_margin` more out-of-play pixels on every side.
func _drawing(a_level: int = 1, a_margin: int = 0) -> MapImageLayers:
	var probe := TerrainData.new()
	probe.play_size = _PLAY
	var side: int = probe.grid_width()
	var layers := MapImageLayers.new()
	layers.size = Vector2i(side, side) + Vector2i.ONE * a_margin * 2
	var terrain := Image.create_empty(layers.size.x, layers.size.y, false, Image.FORMAT_RGBA8)
	terrain.fill(_color(MapImagePalette.Meaning.OUT_OF_PLAY))
	for z: int in side:
		for x: int in side:
			if probe.is_cell_in_play(Vector2i(x, z)):
				terrain.set_pixel(
					x + a_margin,
					z + a_margin,
					_color(MapImagePalette.Meaning.LEVEL_1 + a_level - 1)
				)
	layers.images[MapImagePalette.Layer.TERRAIN] = terrain
	for layer: int in [
		MapImagePalette.Layer.WATER, MapImagePalette.Layer.CLIFFS, MapImagePalette.Layer.STRUCTURES
	]:
		layers.images[layer] = Image.create_empty(
			layers.size.x, layers.size.y, false, Image.FORMAT_RGBA8
		)
	return layers


static func _color(meaning: int) -> Color:
	for entry: Dictionary in MapImagePalette.ENTRIES:
		if entry.meaning == meaning:
			return entry.color
	return Color.TRANSPARENT


## Paint `a_meaning` over the cells of `a_rect` on its layer, keeping to cells in play on the
## terrain layer so the frame stays a diamond.
func _paint(a_layers: MapImageLayers, a_meaning: int, a_rect: Rect2i) -> void:
	var layer: int = _layer_of(a_meaning)
	var image: Image = a_layers.images[layer]
	var terrain: Image = a_layers.images[MapImagePalette.Layer.TERRAIN]
	var out_of_play: Color = _color(MapImagePalette.Meaning.OUT_OF_PLAY)
	var rect: Rect2i = a_rect.intersection(Rect2i(Vector2i.ZERO, a_layers.size))
	for z: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			if terrain.get_pixel(x, z) != out_of_play:
				image.set_pixel(x, z, _color(a_meaning))


static func _layer_of(meaning: int) -> int:
	for entry: Dictionary in MapImagePalette.ENTRIES:
		if entry.meaning == meaning:
			return entry.layer
	return -1


## Level `a_west` west of column _MIDDLE and `a_east` from it on.
func _halves(a_west: int, a_east: int) -> MapImageLayers:
	var layers: MapImageLayers = _drawing(a_west)
	var level: int = MapImagePalette.Meaning.LEVEL_1 + a_east - 1
	_paint(layers, level, Rect2i(_MIDDLE, 0, 100, 100))
	return layers


func _import(a_layers: MapImageLayers) -> MapImageImporter:
	return MapImageImporter.import_layers(a_layers, _params)


func _heights_terrain(a_result: MapImageImporter) -> TerrainData:
	return a_result.map.terrain


func _errors_mention(a_result: MapImageImporter, a_text: String) -> bool:
	for error: String in a_result.errors:
		if error.contains(a_text):
			return true
	return false


#endregion


#region Palette
func test_every_palette_colour_reads_back_as_its_meaning() -> void:
	for entry: Dictionary in MapImagePalette.ENTRIES:
		var color: Color = entry.color
		assert_eq(
			MapImagePalette.meaning_of(entry.layer, color.r8, color.g8, color.b8, color.a8),
			entry.meaning,
			"%s on layer %d" % [MapImagePalette.hex(color), entry.layer]
		)


func test_a_colour_off_by_one_is_unknown_not_nearest() -> void:
	var level_1: Color = _color(MapImagePalette.Meaning.LEVEL_1)
	assert_eq(
		MapImagePalette.meaning_of(
			MapImagePalette.Layer.TERRAIN, level_1.r8 + 1, level_1.g8, level_1.b8, 255
		),
		-1
	)


func test_an_empty_pixel_is_nothing_except_on_terrain() -> void:
	assert_eq(MapImagePalette.meaning_of(MapImagePalette.Layer.WATER, 1, 2, 3, 0), 0)
	assert_eq(MapImagePalette.meaning_of(MapImagePalette.Layer.TERRAIN, 0, 0, 0, 0), -1)


func test_every_meaning_has_a_label() -> void:
	for entry: Dictionary in MapImagePalette.ENTRIES:
		assert_true(MapImagePalette.LABELS.has(entry.meaning), "label for %d" % entry.meaning)


#endregion


#region Classification and frame
func test_a_flat_drawing_imports_at_its_level() -> void:
	var result: MapImageImporter = _import(_drawing(3))
	assert_true(result.is_valid(), "\n".join(result.errors))
	assert_eq(result.map.play_size, _PLAY)
	var terrain: TerrainData = _heights_terrain(result)
	assert_almost_eq(terrain.cell_mean_height(Vector2i(12, 12)), _params.level_height(3), 1e-5)


func test_a_margin_of_out_of_play_shifts_the_frame() -> void:
	var result: MapImageImporter = _import(_drawing(2, 3))
	assert_true(result.is_valid(), "\n".join(result.errors))
	assert_eq(result.map.play_size, _PLAY)
	assert_eq(result.cells.offset, Vector2i(3, 3))


func test_an_unknown_colour_fails_naming_it_and_where() -> void:
	var layers: MapImageLayers = _drawing()
	(layers.images[MapImagePalette.Layer.TERRAIN] as Image).set_pixel(12, 12, Color8(1, 2, 3))
	var result: MapImageImporter = _import(layers)
	assert_false(result.is_valid())
	assert_true(_errors_mention(result, "#010203"), "\n".join(result.errors))
	assert_true(_errors_mention(result, "(12, 12)"), "\n".join(result.errors))


func test_a_painted_extent_that_is_not_a_diamond_fails() -> void:
	var layers: MapImageLayers = _drawing()
	# A corner pixel of the grid is never in play.
	(layers.images[MapImagePalette.Layer.TERRAIN] as Image).set_pixel(
		0, 0, _color(MapImagePalette.Meaning.LEVEL_1)
	)
	var result: MapImageImporter = _import(layers)
	assert_false(result.is_valid())
	assert_true(_errors_mention(result, "not exactly a play diamond"), "\n".join(result.errors))


func test_water_drawn_out_of_play_fails() -> void:
	var layers: MapImageLayers = _drawing()
	(layers.images[MapImagePalette.Layer.WATER] as Image).set_pixel(
		0, 0, _color(MapImagePalette.Meaning.DEEP)
	)
	var result: MapImageImporter = _import(layers)
	assert_true(_errors_mention(result, "out of play"), "\n".join(result.errors))


#endregion


#region Levels, smoothing, cliffs and ramps
func test_unsmoothed_levels_step_by_level_step() -> void:
	var result: MapImageImporter = _import(_halves(1, 2))
	var terrain: TerrainData = _heights_terrain(result)
	assert_almost_eq(terrain.cell_mean_height(Vector2i(6, 12)), _params.level_height(1), 1e-5)
	assert_almost_eq(terrain.cell_mean_height(Vector2i(18, 12)), _params.level_height(2), 1e-5)


func test_smoothing_grades_a_step_with_no_cliff_drawn() -> void:
	_params.smoothing_radius = 2
	var result: MapImageImporter = _import(_halves(1, 3))
	var terrain: TerrainData = _heights_terrain(result)
	for x: int in range(6, 19):
		assert_lte(
			terrain.cell_height_spread(Vector2i(x, 12)),
			TerrainGrid.MAX_SLOPE_DIFF,
			"cell %d graded walkable" % x
		)


func test_a_thin_cliff_keeps_a_sheer_face_through_smoothing() -> void:
	_params.smoothing_radius = 2
	var layers: MapImageLayers = _halves(1, 4)
	_paint(layers, MapImagePalette.Meaning.CLIFF, Rect2i(_MIDDLE, 0, 1, 100))
	var result: MapImageImporter = _import(layers)
	assert_true(result.is_valid(), "\n".join(result.errors))
	assert_gt(
		_heights_terrain(result).cell_height_spread(Vector2i(_MIDDLE, 12)),
		TerrainGrid.MAX_SLOPE_DIFF
	)


func test_a_cliff_across_a_walkable_step_fails_as_walkable() -> void:
	_params.level_step = _WALKABLE_STEP
	var layers: MapImageLayers = _halves(1, 2)
	_paint(layers, MapImagePalette.Meaning.CLIFF, Rect2i(_MIDDLE, 0, 1, 100))
	var result: MapImageImporter = _import(layers)
	assert_false(result.is_valid())
	assert_true(_errors_mention(result, "walkable"), "\n".join(result.errors))


func test_a_wide_cliff_fails_as_walkable() -> void:
	var layers: MapImageLayers = _halves(1, 4)
	_paint(layers, MapImagePalette.Meaning.CLIFF, Rect2i(_MIDDLE - 5, 0, 10, 100))
	assert_true(_errors_mention(_import(layers), "walkable"))


func test_a_wide_ramp_grades_linearly_and_walkably() -> void:
	var layers: MapImageLayers = _halves(1, 4)
	_paint(layers, MapImagePalette.Meaning.RAMP, Rect2i(_MIDDLE - 3, 8, 6, 9))
	var result: MapImageImporter = _import(layers)
	assert_true(result.is_valid(), "\n".join(result.errors))
	var terrain: TerrainData = _heights_terrain(result)
	var previous: float = -INF
	for x: int in range(_MIDDLE - 3, _MIDDLE + 3):
		var cell := Vector2i(x, 12)
		assert_lte(terrain.cell_height_spread(cell), TerrainGrid.MAX_SLOPE_DIFF)
		assert_gt(terrain.cell_mean_height(cell), previous, "rises steadily across the ramp")
		previous = terrain.cell_mean_height(cell)


func test_a_narrow_ramp_across_a_big_drop_fails_as_too_steep() -> void:
	var layers: MapImageLayers = _halves(1, 6)
	_paint(layers, MapImagePalette.Meaning.RAMP, Rect2i(_MIDDLE, 8, 1, 9))
	assert_true(_errors_mention(_import(layers), "too steep"))


## Rough ground is steep on its own level, and leaves the ground beside it as it was.
func test_rough_ground_is_steep_and_its_neighbours_are_not() -> void:
	var layers: MapImageLayers = _drawing(2)
	_paint(layers, MapImagePalette.Meaning.ROUGH, Rect2i(10, 10, 4, 4))
	var result: MapImageImporter = _import(layers)
	assert_true(result.is_valid(), "\n".join(result.errors))
	var terrain: TerrainData = _heights_terrain(result)
	for z: int in range(10, 14):
		for x: int in range(10, 14):
			assert_gt(
				terrain.cell_height_spread(Vector2i(x, z)),
				TerrainGrid.MAX_SLOPE_DIFF,
				"rough cell %s" % Vector2i(x, z)
			)
	for cell: Vector2i in [Vector2i(9, 11), Vector2i(14, 12), Vector2i(11, 9), Vector2i(12, 14)]:
		assert_lte(
			terrain.cell_height_spread(cell), TerrainGrid.MAX_SLOPE_DIFF, "neighbour %s" % cell
		)
	assert_almost_eq(terrain.cell_mean_height(Vector2i(9, 11)), _params.level_height(2), 1e-5)


## A rough line one cell wide has no corner only rough cells share, so it cannot be built steep:
## left level rather than making the ground either side of it steep.
func test_a_rough_line_one_cell_wide_leaves_its_neighbours_walkable() -> void:
	var layers: MapImageLayers = _drawing(2)
	_paint(layers, MapImagePalette.Meaning.ROUGH, Rect2i(_MIDDLE, 0, 1, 100))
	var terrain: TerrainData = _heights_terrain(_import(layers))
	assert_lte(
		terrain.cell_height_spread(Vector2i(_MIDDLE - 1, _MIDDLE)), TerrainGrid.MAX_SLOPE_DIFF
	)


func test_a_chasm_floor_is_below_its_rim_and_steep_everywhere() -> void:
	var layers: MapImageLayers = _drawing(3)
	_paint(layers, MapImagePalette.Meaning.CHASM, Rect2i(10, 10, 5, 5))
	var result: MapImageImporter = _import(layers)
	assert_true(result.is_valid(), "\n".join(result.errors))
	var terrain: TerrainData = _heights_terrain(result)
	for z: int in range(10, 15):
		for x: int in range(10, 15):
			var cell := Vector2i(x, z)
			assert_gt(terrain.cell_height_spread(cell), TerrainGrid.MAX_SLOPE_DIFF, "%s" % cell)
			assert_lt(terrain.cell_mean_height(cell), _params.level_height(3))


func test_a_one_cell_chasm_is_still_unstandable() -> void:
	var layers: MapImageLayers = _drawing(2)
	_paint(layers, MapImagePalette.Meaning.CHASM, Rect2i(12, 4, 1, 17))
	var terrain: TerrainData = _heights_terrain(_import(layers))
	assert_gt(terrain.cell_height_spread(Vector2i(12, 12)), TerrainGrid.MAX_SLOPE_DIFF)


func test_smoothing_that_eats_a_feature_is_listed() -> void:
	_params.smoothing_radius = 3
	var layers: MapImageLayers = _drawing(1)
	_paint(layers, MapImagePalette.Meaning.LEVEL_6, Rect2i(12, 12, 1, 1))
	var result: MapImageImporter = _import(layers)
	assert_true(result.is_valid(), "\n".join(result.errors))
	assert_true(
		Array(result.notes).any(func(n: String) -> bool: return n.contains("smoothing ate")),
		"\n".join(result.notes)
	)


func test_edge_noise_is_seeded_and_zero_is_off() -> void:
	var layers: MapImageLayers = _halves(1, 2)
	var flat: PackedFloat32Array = _import(layers).relief.heights
	_params.edge_noise_cells = 2.0
	_params.edge_noise_seed = 7
	var first: PackedFloat32Array = _import(_halves(1, 2)).relief.heights
	var second: PackedFloat32Array = _import(_halves(1, 2)).relief.heights
	assert_eq(first, second, "same seed, same map")
	assert_ne(first, flat, "the noise moved an edge")


#endregion


#region Water
func test_a_lake_stands_below_its_lowest_bank_and_is_deep() -> void:
	var layers: MapImageLayers = _drawing(2)
	_paint(layers, MapImagePalette.Meaning.DEEP, Rect2i(9, 9, 7, 7))
	var result: MapImageImporter = _import(layers)
	assert_true(result.is_valid(), "\n".join(result.errors))
	assert_eq(result.map.waters.size(), 1)
	var water: Dictionary = result.map.waters[0]
	assert_almost_eq(water.level, _params.level_height(2) - MapImageWater.WATER_OFFSET, 1e-5)
	var basin: WaterBasin = WaterBasin.fill(result.map.terrain, water.seed_cell, water.level)
	assert_true(basin.is_valid())
	assert_gt(basin.depth_at(Vector2i(12, 12)), WaterBasin.WADE_DEPTH)
	assert_false(basin.depth_by_cell.has(Vector2i(5, 12)), "the water stays in its banks")


func test_shallow_water_is_wadeable() -> void:
	var layers: MapImageLayers = _drawing(2)
	_paint(layers, MapImagePalette.Meaning.SHALLOW, Rect2i(9, 9, 7, 7))
	var result: MapImageImporter = _import(layers)
	var water: Dictionary = result.map.waters[0]
	var basin: WaterBasin = WaterBasin.fill(result.map.terrain, water.seed_cell, water.level)
	var depth: float = basin.depth_at(Vector2i(12, 12))
	assert_gt(depth, 0.0)
	assert_lte(depth, WaterBasin.WADE_DEPTH)


func test_water_between_two_levels_takes_the_lower_bank() -> void:
	var layers: MapImageLayers = _halves(1, 2)
	_paint(layers, MapImagePalette.Meaning.SHALLOW, Rect2i(10, 9, 2, 7))
	var result: MapImageImporter = _import(layers)
	assert_almost_eq(
		result.map.waters[0].level, _params.level_height(1) - MapImageWater.WATER_OFFSET, 1e-5
	)


func test_a_waterfall_is_skipped_as_dry_ground_and_reported() -> void:
	var layers: MapImageLayers = _halves(1, 3)
	_paint(layers, MapImagePalette.Meaning.DEEP, Rect2i(9, 10, 6, 5))
	var result: MapImageImporter = _import(layers)
	assert_true(result.is_valid(), "\n".join(result.errors))
	assert_eq(result.map.waters.size(), 0)
	assert_true(Array(result.notes).any(func(n: String) -> bool: return n.contains("waterfall")))


func test_a_lithium_pond_is_charged_by_size_and_richness() -> void:
	var layers: MapImageLayers = _drawing(2)
	_paint(layers, MapImagePalette.Meaning.LITHIUM_RICH, Rect2i(10, 10, 4, 4))
	var result: MapImageImporter = _import(layers)
	var ponds: Array[MapFeature] = result.map.features_of(MapFeature.Kind.POND)
	assert_eq(ponds.size(), 1)
	var rich: int = _params.generation.pond_richness_factors[2]
	assert_eq(ponds[0].pond_charge, mini(16 * rich, _params.generation.pond_charge_max))
	assert_true(
		WaterBasin.fill(result.map.terrain, ponds[0].pond_seed_cell, ponds[0].pond_level).is_valid()
	)


func test_a_pond_drawn_in_two_richnesses_fails() -> void:
	var layers: MapImageLayers = _drawing(2)
	_paint(layers, MapImagePalette.Meaning.LITHIUM_RICH, Rect2i(10, 10, 2, 4))
	_paint(layers, MapImagePalette.Meaning.LITHIUM_POOR, Rect2i(12, 10, 2, 4))
	assert_true(_errors_mention(_import(layers), "more than one richness"))


#endregion


#region Structures
func test_a_shelter_and_buildings_match_their_footprints_and_turns() -> void:
	var layers: MapImageLayers = _drawing(2)
	_paint(layers, MapImagePalette.Meaning.SHELTER, Rect2i(8, 8, 3, 3))
	_paint(layers, MapImagePalette.Meaning.BUILDING, Rect2i(14, 8, 5, 3))
	_paint(layers, MapImagePalette.Meaning.BUILDING, Rect2i(9, 14, 4, 4))
	var result: MapImageImporter = _import(layers)
	assert_true(result.is_valid(), "\n".join(result.errors))
	var placed: Dictionary = {}
	for placement: Dictionary in result.structures.placements:
		placed[(placement.piece as MapPiece).id] = placement
	assert_eq(placed.keys().size(), 3)
	assert_eq(placed[&"fake_long"].quarter_turns, 1, "drawn 5 x 3, so turned")
	assert_eq(placed[&"fake_long"].origin, Vector2i(14, 8))
	assert_eq(placed[&"fake_square"].origin, Vector2i(9, 14))
	assert_eq(result.map.features_of(MapFeature.Kind.SHELTER).size(), 1)


func test_a_footprint_matching_no_piece_fails() -> void:
	var layers: MapImageLayers = _drawing(2)
	_paint(layers, MapImagePalette.Meaning.BUILDING, Rect2i(10, 10, 2, 3))
	assert_true(_errors_mention(_import(layers), "matches no piece"))


func test_structures_that_touch_diagonally_fail() -> void:
	var layers: MapImageLayers = _drawing(2)
	_paint(layers, MapImagePalette.Meaning.SHELTER, Rect2i(8, 8, 3, 3))
	_paint(layers, MapImagePalette.Meaning.BUILDING, Rect2i(11, 11, 4, 4))
	assert_true(_errors_mention(_import(layers), "touches"))


func test_a_structure_across_two_levels_fails() -> void:
	var layers: MapImageLayers = _halves(1, 2)
	_paint(layers, MapImagePalette.Meaning.BUILDING, Rect2i(_MIDDLE - 2, 10, 4, 4))
	assert_true(_errors_mention(_import(layers), "straddles"))


func test_a_footprint_is_flattened_through_smoothing() -> void:
	_params.smoothing_radius = 3
	var layers: MapImageLayers = _halves(1, 3)
	_paint(layers, MapImagePalette.Meaning.BUILDING, Rect2i(_MIDDLE + 1, 10, 4, 4))
	var terrain: TerrainData = _heights_terrain(_import(layers))
	for z: int in range(10, 14):
		for x: int in range(_MIDDLE + 1, _MIDDLE + 5):
			assert_true(terrain.cell_is_flat(Vector2i(x, z)), "footprint cell (%d, %d)" % [x, z])


func test_start_points_are_single_pixels() -> void:
	var layers: MapImageLayers = _drawing(2)
	_paint(layers, MapImagePalette.Meaning.START, Rect2i(6, 12, 1, 1))
	_paint(layers, MapImagePalette.Meaning.START, Rect2i(18, 12, 1, 1))
	var result: MapImageImporter = _import(layers)
	assert_eq(result.map.starts.size(), 2)
	assert_eq(result.map.starts[0].position, Vector2(6.5, 12.5))
	_paint(layers, MapImagePalette.Meaning.START, Rect2i(12, 6, 2, 1))
	assert_true(_errors_mention(_import(layers), "one pixel"))


#endregion


#region Re-import flags
func test_a_hand_placed_structure_on_new_slope_or_overlap_is_flagged() -> void:
	_params.smoothing_radius = 2
	var result: MapImageImporter = _import(_halves(1, 4))
	var pieces: Array[Dictionary] = [
		{name = "OnFlat", rect = Rect2i(3, 11, 2, 2), is_fixture = true},
		{name = "OnSlope", rect = Rect2i(_MIDDLE - 1, 11, 2, 2), is_fixture = true},
		{name = "Under", rect = Rect2i(18, 11, 2, 2), is_fixture = true},
	]
	var imported: Array[Rect2i] = [Rect2i(19, 12, 2, 2)]
	var flags: Dictionary = MapImageReimport.flag(result.map.terrain, {}, imported, pieces)
	var text: String = "\n".join(flags.lines)
	assert_false(text.contains("OnFlat"), text)
	assert_true(text.contains("OnSlope") and text.contains("slope"), text)
	assert_true(text.contains("Under") and text.contains("overlaps"), text)


#endregion


#region File formats
func test_open_raster_round_trips_layers() -> void:
	var layers: MapImageLayers = _drawing(4)
	var path: String = "user://test_map_image.ora"
	var named: Array[Dictionary] = [
		{name = "water", image = layers.images[MapImagePalette.Layer.WATER]},
		{name = "terrain", image = layers.images[MapImagePalette.Layer.TERRAIN]},
	]
	assert_eq(OpenRaster.write(path, layers.size, named), OK)
	var read: MapImageLayers = OpenRaster.read(path)
	assert_true(read.is_valid(), "\n".join(read.errors))
	assert_eq(
		(read.images[MapImagePalette.Layer.TERRAIN] as Image).get_data(),
		(layers.images[MapImagePalette.Layer.TERRAIN] as Image).get_data()
	)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_open_raster_rejects_an_unknown_layer_name() -> void:
	var layers: MapImageLayers = _drawing()
	var path: String = "user://test_map_image_bad.ora"
	var named: Array[Dictionary] = [
		{name = "terrain", image = layers.images[MapImagePalette.Layer.TERRAIN]},
		{name = "Sketch notes", image = layers.images[MapImagePalette.Layer.WATER]},
	]
	OpenRaster.write(path, layers.size, named)
	var read: MapImageLayers = OpenRaster.read(path)
	assert_false(read.is_valid())
	assert_true("\n".join(read.errors).contains("Sketch notes"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_aseprite_compressed_and_raw_cels_decode_exactly() -> void:
	var size := Vector2i(6, 4)
	var cel := Image.create_empty(3, 2, false, Image.FORMAT_RGBA8)
	cel.fill(Color8(0xAF, 0xCE, 0x8C))
	cel.set_pixel(1, 1, Color8(0, 0, 0, 128))
	var bytes: PackedByteArray = _aseprite(
		size,
		["terrain", "cliffs"],
		[
			{layer = 0, position = Vector2i(2, 1), image = cel, compressed = true},
			{layer = 1, position = Vector2i(0, 0), image = cel, compressed = false},
		]
	)
	var decoded: Dictionary = AsepriteFile.decode(bytes)
	assert_eq(decoded.error, "")
	assert_eq(decoded.size, size)
	assert_eq(decoded.layers.size(), 2)
	var terrain: Image = decoded.layers[0].image
	assert_eq(decoded.layers[0].name, "terrain")
	assert_eq(terrain.get_pixel(2, 1), Color8(0xAF, 0xCE, 0x8C))
	assert_eq(terrain.get_pixel(3, 2).a8, 128)
	assert_eq(terrain.get_pixel(0, 0).a8, 0, "outside the cel is empty")
	assert_eq((decoded.layers[1].image as Image).get_pixel(1, 1).a8, 128)


func test_aseprite_converts_to_an_ora_beside_it() -> void:
	var terrain: Image = _drawing(5).images[MapImagePalette.Layer.TERRAIN]
	var bytes: PackedByteArray = _aseprite(
		terrain.get_size(),
		["terrain"],
		[{layer = 0, position = Vector2i.ZERO, image = terrain, compressed = true}]
	)
	var path: String = "user://test_map_image.aseprite"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()
	var result: MapImageImporter = MapImageImporter.import_path(path, _params)
	assert_true(result.is_valid(), "\n".join(result.errors))
	assert_true(FileAccess.file_exists("user://test_map_image.ora"))
	assert_almost_eq(
		result.map.terrain.cell_mean_height(Vector2i(12, 12)), _params.level_height(5), 1e-5
	)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_map_image.ora"))


## A minimal RGBA `.aseprite` file: one frame, `names` as normal layers, `cels` on them.
func _aseprite(a_size: Vector2i, a_names: Array, a_cels: Array) -> PackedByteArray:
	var chunks := StreamPeerBuffer.new()
	var count: int = 0
	for name: String in a_names:
		var body := StreamPeerBuffer.new()
		body.put_u16(1)  # visible
		body.put_u16(0)  # normal layer
		body.put_u16(0)
		body.put_u16(0)
		body.put_u16(0)
		body.put_u16(0)
		body.put_u8(255)
		body.put_data(PackedByteArray([0, 0, 0]))
		body.put_u16(name.length())
		body.put_data(name.to_utf8_buffer())
		_chunk(chunks, AsepriteFile.CHUNK_LAYER, body.data_array)
		count += 1
	for cel: Dictionary in a_cels:
		var image: Image = cel.image
		var body := StreamPeerBuffer.new()
		body.put_u16(cel.layer)
		body.put_16(cel.position.x)
		body.put_16(cel.position.y)
		body.put_u8(255)
		body.put_u16(AsepriteFile.CEL_COMPRESSED if cel.compressed else AsepriteFile.CEL_RAW)
		body.put_16(0)
		body.put_data(PackedByteArray([0, 0, 0, 0, 0]))
		body.put_u16(image.get_width())
		body.put_u16(image.get_height())
		var pixels: PackedByteArray = image.get_data()
		body.put_data(pixels.compress(FileAccess.COMPRESSION_DEFLATE) if cel.compressed else pixels)
		_chunk(chunks, AsepriteFile.CHUNK_CEL, body.data_array)
		count += 1
	var frame := StreamPeerBuffer.new()
	frame.put_u32(AsepriteFile.FRAME_HEADER_BYTES + chunks.data_array.size())
	frame.put_u16(AsepriteFile.FRAME_MAGIC)
	frame.put_u16(count)
	frame.put_u16(100)
	frame.put_u16(0)
	frame.put_u32(count)
	frame.put_data(chunks.data_array)
	var header := StreamPeerBuffer.new()
	header.put_u32(AsepriteFile.HEADER_BYTES + frame.data_array.size())
	header.put_u16(AsepriteFile.HEADER_MAGIC)
	header.put_u16(1)
	header.put_u16(a_size.x)
	header.put_u16(a_size.y)
	header.put_u16(AsepriteFile.DEPTH_RGBA)
	var padding := PackedByteArray()
	padding.resize(AsepriteFile.HEADER_BYTES - header.data_array.size())
	header.put_data(padding)
	return header.data_array + frame.data_array


func _chunk(a_out: StreamPeerBuffer, a_type: int, a_body: PackedByteArray) -> void:
	a_out.put_u32(AsepriteFile.CHUNK_HEADER_BYTES + a_body.size())
	a_out.put_u16(a_type)
	a_out.put_data(a_body)


#endregion


#region Water through smoothing
## Regression (2026-10-22): a shallow ford joined to a deep lake came back dry at the default
## smoothing, because the deep bed dragged the smoothed banks — and the level read off them —
## below the shallow bed.
func test_a_shallow_ford_beside_a_deep_lake_stays_wadeable_water() -> void:
	_params.smoothing_radius = 2
	var layers: MapImageLayers = _drawing(2)
	_paint(layers, MapImagePalette.Meaning.DEEP, Rect2i(9, 9, 7, 7))
	_paint(layers, MapImagePalette.Meaning.SHALLOW, Rect2i(16, 11, 6, 3))
	var result: MapImageImporter = _import(layers)
	assert_true(result.is_valid(), "\n".join(result.errors))
	assert_eq(result.map.waters.size(), 1, "\n".join(result.notes))
	var water: Dictionary = result.map.waters[0]
	var basin: WaterBasin = WaterBasin.fill(result.map.terrain, water.seed_cell, water.level)
	for x: int in range(16, 22):
		for z: int in range(11, 14):
			var depth: float = basin.depth_at(Vector2i(x, z))
			assert_gt(depth, 0.0, "ford cell (%d, %d) is wet" % [x, z])
			assert_lte(depth, WaterBasin.WADE_DEPTH, "ford cell (%d, %d) is wadeable" % [x, z])
	for x: int in range(10, 15):
		assert_gt(
			basin.depth_at(Vector2i(x, 12)), WaterBasin.WADE_DEPTH, "lake cell %d is deep" % x
		)
	assert_false(basin.depth_by_cell.has(Vector2i(19, 10)), "the bank beside the ford stays dry")


func test_a_shallow_strip_running_off_the_play_edge_stays_water() -> void:
	_params.smoothing_radius = 2
	var layers: MapImageLayers = _drawing(2)
	_paint(layers, MapImagePalette.Meaning.SHALLOW, Rect2i(11, 0, 3, 13))
	var result: MapImageImporter = _import(layers)
	assert_eq(result.map.waters.size(), 1, "\n".join(result.notes))
	var water: Dictionary = result.map.waters[0]
	var basin: WaterBasin = WaterBasin.fill(result.map.terrain, water.seed_cell, water.level)
	assert_gt(basin.depth_at(Vector2i(12, 8)), 0.0)
	assert_lte(basin.depth_at(Vector2i(12, 8)), WaterBasin.WADE_DEPTH)


#endregion


#region Marking a refused drawing
## Each error that names pixels is one issue, numbered and coloured in the report, and its pixels
## marked in that colour on the readout, in the drawing's own pixel frame less its margin.
func test_a_refused_drawing_marks_each_issue_in_its_colour() -> void:
	var layers: MapImageLayers = _drawing(1, _MARGIN)
	var stray := Vector2i(_MARGIN + _MIDDLE, _MARGIN + _MIDDLE)
	(layers.images[MapImagePalette.Layer.TERRAIN] as Image).set_pixelv(stray, Color8(1, 2, 3))
	var result: MapImageImporter = _import(layers)
	assert_false(result.is_valid())
	var issues: Array[Dictionary] = MapImageIssues.of(result)
	assert_eq(issues.size(), 1, "\n".join(result.errors))
	assert_has(issues[0].pixels, stray)
	assert_string_contains(MapImageImportReport.lines(result, "t")[2], "[1, red]")
	var readout: Image = MapImageImportReport.readout(result, _params)
	assert_eq(
		readout.get_pixelv(stray - result.cells.offset).to_rgba32(),
		MapImageIssues.COLORS[0].to_rgba32()
	)


func test_a_drawing_refused_before_it_is_classified_has_no_marked_issues() -> void:
	var result: MapImageImporter = MapImageImporter.import_layers(
		MapImageLayers.failed("unreadable"), _params
	)
	assert_eq(MapImageIssues.of(result).size(), 0)
#endregion
