extends GutTest

## The map image exporter's pure core (map-from-image.md §Exporting a map to a drawing): a
## synthetic drawing imported with smoothing and noise off and exported again comes back pixel
## for pixel, and each loss the note lists is checked on its own. Structures are matched against
## fake footprints, as in test_MapImageImporter, so a retuned shelter cannot fail this file.

## 12 x 12 diamonds: a 25 x 25 cell grid, the drawing's pixels one to one.
const _PLAY := Vector2i(12, 12)
const _MIDDLE: int = 12
const _SHELTER := Vector2i(3, 3)
const _SQUARE := Vector2i(4, 4)
## Differing cells named in a failure; the count covers the rest.
const _LISTED_DIFFERENCES: int = 8
## A patch of shallow water whose bed is roughened past the walkable slope, and how far its
## corners are pushed up and down.
const _ROUGH_BED := Rect2i(9, 9, 7, 7)
const _BED_ROUGHNESS: float = 0.4
## A level step the map is built at that the exporter is not told about.
const _OTHER_STEP: float = 1.8
## Columns per level in the six-band drawing, and the block of the top band raised to a seventh
## terrace: inside the band and the diamond, and big enough to count as a terrace.
const _BAND: int = 4
const _SEVENTH := Rect2i(12, 8, 4, 8)
## The block is in the level-4 band: three steps up puts it one past level 6.
const _SEVENTH_RISE: float = MapGenerationParams.LEVEL_STEP * 3.0
const _EXPORT_PATH: String = "user://test_map_image_export.ora"

var _params: MapImageImportParams


func before_each() -> void:
	_params = MapImageImportParams.new()
	_params.edge_noise_cells = 0.0
	_params.smoothing_radius = 0
	_params.generation.shelter_piece = MapPiece.of(&"fake_shelter", _SHELTER)
	_params.generation.building_pool.assign([MapPiece.of(&"fake_square", _SQUARE)])


func after_all() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_EXPORT_PATH))


#region Helpers
## A drawing of `_PLAY` in play, every cell `a_level`, beyond it the out-of-play colour.
func _drawing(a_level: int = 1) -> MapImageLayers:
	var probe := TerrainData.new()
	probe.play_size = _PLAY
	var side: int = probe.grid_width()
	var layers := MapImageLayers.new()
	layers.size = Vector2i(side, side)
	var terrain := Image.create_empty(side, side, false, Image.FORMAT_RGBA8)
	terrain.fill(_color(MapImagePalette.Meaning.OUT_OF_PLAY))
	for z: int in side:
		for x: int in side:
			if probe.is_cell_in_play(Vector2i(x, z)):
				terrain.set_pixel(x, z, _color(MapImagePalette.Meaning.LEVEL_1 + a_level - 1))
	layers.images[MapImagePalette.Layer.TERRAIN] = terrain
	for layer: int in [
		MapImagePalette.Layer.WATER, MapImagePalette.Layer.CLIFFS, MapImagePalette.Layer.STRUCTURES
	]:
		layers.images[layer] = Image.create_empty(side, side, false, Image.FORMAT_RGBA8)
	return layers


static func _color(meaning: int) -> Color:
	for entry: Dictionary in MapImagePalette.ENTRIES:
		if entry.meaning == meaning:
			return entry.color
	return Color.TRANSPARENT


static func _layer_of(meaning: int) -> int:
	for entry: Dictionary in MapImagePalette.ENTRIES:
		if entry.meaning == meaning:
			return entry.layer
	return -1


## Paint `a_meaning` over `a_rect`, keeping to cells in play so the frame stays a diamond.
func _paint(a_layers: MapImageLayers, a_meaning: int, a_rect: Rect2i) -> void:
	var image: Image = a_layers.images[_layer_of(a_meaning)]
	var terrain: Image = a_layers.images[MapImagePalette.Layer.TERRAIN]
	var out_of_play: Color = _color(MapImagePalette.Meaning.OUT_OF_PLAY)
	var rect: Rect2i = a_rect.intersection(Rect2i(Vector2i.ZERO, a_layers.size))
	for z: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			if terrain.get_pixel(x, z) != out_of_play:
				image.set_pixel(x, z, _color(a_meaning))


## Import `a_layers`, then export the map that made, as the dock exports one an import placed.
func _round_trip(a_layers: MapImageLayers) -> MapImageExporter:
	var imported: MapImageImporter = MapImageImporter.import_layers(a_layers, _params)
	assert_true(imported.is_valid(), "\n".join(imported.errors))
	return _export(imported.map)


func _export(a_map: GeneratedMap) -> MapImageExporter:
	var waters: Array[Dictionary] = []
	for water: Dictionary in a_map.waters:
		waters.append({seed_cell = water.seed_cell, level = water.level, energy = 0})
	var pieces: Array[Dictionary] = []
	for feature: MapFeature in a_map.features:
		if feature.kind == MapFeature.Kind.POND:
			(
				waters
				. append(
					{
						seed_cell = feature.pond_seed_cell,
						level = feature.pond_level,
						energy = feature.pond_charge,
					}
				)
			)
			continue
		for placement: Dictionary in feature.placements:
			(
				pieces
				. append(
					{
						id = (placement.piece as MapPiece).id,
						rect = MapFeature.placement_rect(placement),
					}
				)
			)
	var starts: Array[Vector2i] = []
	for start: MapStart in a_map.starts:
		starts.append(Vector2i(start.position.floor()))
	var out: MapImageExporter = MapImageExporter.export_parts(
		a_map.terrain, waters, pieces, starts, _params
	)
	assert_true(out.is_valid(), "\n".join(out.errors))
	return out


## Assert `a_exported`'s layer holds what `a_drawn`'s does, away from the play area's edge,
## naming the first cells that differ. A cell on the edge shares corners with ground out of
## play, so its height — and the level it is read back as — is the edge's, not its own.
func _assert_same_layer(
	a_exported: MapImageExporter, a_drawn: MapImageLayers, a_layer: int
) -> void:
	var differ: PackedStringArray = PackedStringArray()
	var count: int = 0
	var drawn: Image = a_drawn.images[a_layer]
	for z: int in a_exported.size.y:
		for x: int in a_exported.size.x:
			var cell := Vector2i(x, z)
			if not _is_interior(a_drawn, cell):
				continue
			var color: Color = drawn.get_pixelv(cell)
			var want: int = MapImagePalette.meaning_of(
				a_layer, color.r8, color.g8, color.b8, color.a8
			)
			var got: int = _meaning_at(a_exported, a_layer, cell)
			if got != want:
				count += 1
				if differ.size() < _LISTED_DIFFERENCES:
					differ.append("%s drawn %d exported %d" % [cell, want, got])
	assert_eq(count, 0, "%s layer: %s" % [MapImagePalette.LAYER_NAMES[a_layer], ", ".join(differ)])


func _is_interior(a_drawn: MapImageLayers, a_cell: Vector2i) -> bool:
	var terrain: Image = a_drawn.images[MapImagePalette.Layer.TERRAIN]
	var out_of_play: Color = _color(MapImagePalette.Meaning.OUT_OF_PLAY)
	for dx: int in range(-1, 2):
		for dz: int in range(-1, 2):
			var near: Vector2i = a_cell + Vector2i(dx, dz)
			if (
				not Rect2i(Vector2i.ZERO, a_drawn.size).has_point(near)
				or terrain.get_pixelv(near) == out_of_play
			):
				return false
	return true


func _meaning_at(a_exported: MapImageExporter, a_layer: int, a_cell: Vector2i) -> int:
	var color: Color = (a_exported.images[a_layer] as Image).get_pixelv(a_cell)
	return MapImagePalette.meaning_of(a_layer, color.r8, color.g8, color.b8, color.a8)


func _notes_mention(a_exported: MapImageExporter, a_text: String) -> bool:
	return Array(a_exported.notes).any(func(note: String) -> bool: return note.contains(a_text))


#endregion


#region Round trips
func test_levels_come_back_pixel_for_pixel() -> void:
	var layers: MapImageLayers = _drawing(1)
	_paint(layers, MapImagePalette.Meaning.LEVEL_2, Rect2i(_MIDDLE, 0, 100, 100))
	_paint(layers, MapImagePalette.Meaning.LEVEL_3, Rect2i(_MIDDLE, 0, 100, 6))
	var exported: MapImageExporter = _round_trip(layers)
	_assert_same_layer(exported, layers, MapImagePalette.Layer.TERRAIN)


func test_water_comes_back_as_the_import_left_it() -> void:
	var layers: MapImageLayers = _drawing(1)
	_paint(layers, MapImagePalette.Meaning.DEEP, Rect2i(8, 8, 5, 5))
	_paint(layers, MapImagePalette.Meaning.SHALLOW, Rect2i(13, 8, 3, 5))
	var exported: MapImageExporter = _round_trip(layers)
	_assert_same_layer(exported, layers, MapImagePalette.Layer.TERRAIN)
	# The import leaves a deep patch's corners wadeable (it reports them), and the export reads
	# the water as it is: those come back shallow, and nothing else moves.
	var water: Image = layers.images[MapImagePalette.Layer.WATER]
	for z: int in exported.size.y:
		for x: int in exported.size.x:
			var cell := Vector2i(x, z)
			var color: Color = water.get_pixelv(cell)
			var drawn: int = MapImagePalette.meaning_of(
				MapImagePalette.Layer.WATER, color.r8, color.g8, color.b8, color.a8
			)
			var got: int = _meaning_at(exported, MapImagePalette.Layer.WATER, cell)
			if drawn == MapImagePalette.Meaning.DEEP and got == MapImagePalette.Meaning.SHALLOW:
				continue
			assert_eq(got, drawn, "water at %s" % cell)


func test_a_pond_comes_back_in_its_richness_shade() -> void:
	var layers: MapImageLayers = _drawing(2)
	_paint(layers, MapImagePalette.Meaning.LITHIUM_RICH, Rect2i(10, 10, 4, 4))
	var exported: MapImageExporter = _round_trip(layers)
	_assert_same_layer(exported, layers, MapImagePalette.Layer.WATER)
	assert_false(_notes_mention(exported, "charge"), "an unchanged charge is not listed")


func test_a_chasm_comes_back_as_a_chasm_and_its_rim_as_ground() -> void:
	var layers: MapImageLayers = _drawing(1)
	_paint(layers, MapImagePalette.Meaning.CHASM, Rect2i(10, 10, 5, 5))
	var exported: MapImageExporter = _round_trip(layers)
	_assert_same_layer(exported, layers, MapImagePalette.Layer.TERRAIN)


func test_structures_and_a_start_come_back_pixel_for_pixel() -> void:
	var layers: MapImageLayers = _drawing(1)
	_paint(layers, MapImagePalette.Meaning.SHELTER, Rect2i(Vector2i(6, 10), _SHELTER))
	_paint(layers, MapImagePalette.Meaning.BUILDING, Rect2i(Vector2i(14, 10), _SQUARE))
	_paint(layers, MapImagePalette.Meaning.START, Rect2i(12, 18, 1, 1))
	var exported: MapImageExporter = _round_trip(layers)
	_assert_same_layer(exported, layers, MapImagePalette.Layer.STRUCTURES)


func test_an_export_written_to_disk_reads_back_as_drawn() -> void:
	var layers: MapImageLayers = _drawing(1)
	_paint(layers, MapImagePalette.Meaning.LEVEL_2, Rect2i(_MIDDLE, 0, 100, 100))
	_paint(layers, MapImagePalette.Meaning.DEEP, Rect2i(4, 10, 4, 4))
	var exported: MapImageExporter = _round_trip(layers)
	assert_eq(exported.write(_EXPORT_PATH), OK)
	var read: MapImageLayers = MapImageLayers.load_path(_EXPORT_PATH)
	assert_true(read.is_valid(), "\n".join(read.errors))
	for layer: int in MapImagePalette.LAYER_NAMES:
		assert_eq(
			(read.images[layer] as Image).get_data(),
			(exported.images[layer] as Image).get_data(),
			MapImagePalette.LAYER_NAMES[layer]
		)


#endregion


#region Losses
## Water only wading-deep over a steep bed cannot be walked, so it is drawn deep: drawn shallow, the
## import laid it on a flat wadeable shelf, and a lake gained a walkable shore it never had.
func test_shallow_water_over_a_steep_bed_is_drawn_deep() -> void:
	var layers: MapImageLayers = _drawing(1)
	_paint(layers, MapImagePalette.Meaning.SHALLOW, _ROUGH_BED)
	var imported: MapImageImporter = MapImageImporter.import_layers(layers, _params)
	var terrain: TerrainData = imported.map.terrain
	var corners_wide: int = terrain.grid_width() + 1
	for z: int in range(_ROUGH_BED.position.y + 1, _ROUGH_BED.end.y):
		for x: int in range(_ROUGH_BED.position.x + 1, _ROUGH_BED.end.x):
			terrain.heights[z * corners_wide + x] += (
				_BED_ROUGHNESS * (1 if (x + z) % 2 == 0 else -1)
			)
	var exported: MapImageExporter = _export(imported.map)
	var middle: Vector2i = _ROUGH_BED.get_center()
	assert_gt(terrain.cell_height_spread(middle), TerrainGrid.MAX_SLOPE_DIFF, "the bed is steep")
	assert_eq(
		_meaning_at(exported, MapImagePalette.Layer.WATER, middle), MapImagePalette.Meaning.DEEP
	)
	assert_false(_notes_mention(exported, "PASSAGE"), "\n".join(exported.notes))


## A band of steep ground on one level is drawn rough and comes back as unwalkable as it was:
## drawn as level ground, it opened a passage the map kept closed.
func test_a_steep_band_on_one_level_comes_back_rough_and_closed() -> void:
	var imported: MapImageImporter = MapImageImporter.import_layers(_drawing(1), _params)
	var terrain: TerrainData = imported.map.terrain
	var corners_wide: int = terrain.grid_width() + 1
	for z: int in terrain.grid_depth() + 1:
		if z % 2 == 0:
			terrain.heights[z * corners_wide + _MIDDLE] += _BED_ROUGHNESS * 2.0
	var exported: MapImageExporter = _export(imported.map)
	assert_eq(
		_meaning_at(exported, MapImagePalette.Layer.CLIFFS, Vector2i(_MIDDLE, _MIDDLE)),
		MapImagePalette.Meaning.ROUGH
	)
	assert_false(_notes_mention(exported, "PASSAGE"), "\n".join(exported.notes))
	assert_not_null(exported.readout())


func test_a_graded_slope_comes_back_as_the_two_levels_it_joined() -> void:
	_params.smoothing_radius = 2
	var layers: MapImageLayers = _drawing(1)
	_paint(layers, MapImagePalette.Meaning.LEVEL_2, Rect2i(_MIDDLE, 0, 100, 100))
	var exported: MapImageExporter = _round_trip(layers)
	var seen: Dictionary = {}
	for x: int in range(2, 23):
		seen[_meaning_at(exported, MapImagePalette.Layer.TERRAIN, Vector2i(x, _MIDDLE))] = true
	var meanings: Array = seen.keys()
	meanings.sort()
	assert_eq(meanings, [MapImagePalette.Meaning.LEVEL_1, MapImagePalette.Meaning.LEVEL_2])
	assert_eq(
		_meaning_at(exported, MapImagePalette.Layer.TERRAIN, Vector2i(4, _MIDDLE)),
		MapImagePalette.Meaning.LEVEL_1
	)
	assert_eq(
		_meaning_at(exported, MapImagePalette.Layer.TERRAIN, Vector2i(20, _MIDDLE)),
		MapImagePalette.Meaning.LEVEL_2
	)


## A cliff comes back on the steep cell at the foot of the step, where the levels put it, and
## re-imports as the same cliff.
func test_a_cliff_comes_back_where_it_was_drawn() -> void:
	var layers: MapImageLayers = _drawing(1)
	_paint(layers, MapImagePalette.Meaning.LEVEL_2, Rect2i(_MIDDLE, 0, 100, 100))
	_paint(layers, MapImagePalette.Meaning.CLIFF, Rect2i(_MIDDLE - 1, 0, 1, 100))
	var exported: MapImageExporter = _round_trip(layers)
	_assert_same_layer(exported, layers, MapImagePalette.Layer.TERRAIN)
	_assert_same_layer(exported, layers, MapImagePalette.Layer.CLIFFS)


## Levels are the map's terraces numbered from its lowest: a map standing wholly on level 3 comes
## back on level 1, its relief kept and its height above the generator's ground not.
func test_the_lowest_terrace_comes_back_as_level_one() -> void:
	var exported: MapImageExporter = _round_trip(_drawing(3))
	assert_eq(
		_meaning_at(exported, MapImagePalette.Layer.TERRAIN, Vector2i(_MIDDLE, _MIDDLE)),
		MapImagePalette.Meaning.LEVEL_1
	)


func test_a_pond_whose_charge_would_change_is_listed() -> void:
	var layers: MapImageLayers = _drawing(2)
	_paint(layers, MapImagePalette.Meaning.LITHIUM_RICH, Rect2i(10, 10, 4, 4))
	var imported: MapImageImporter = MapImageImporter.import_layers(layers, _params)
	for feature: MapFeature in imported.map.features:
		if feature.kind == MapFeature.Kind.POND:
			feature.pond_charge += 1
	assert_true(_notes_mention(_export(imported.map), "charge"))


func test_structures_the_import_would_refuse_are_removed_and_listed() -> void:
	var terrain: TerrainData = MapImageImporter.import_layers(_drawing(1), _params).map.terrain
	var touching: Array[Dictionary] = [
		{id = &"fake_square", rect = Rect2i(Vector2i(8, 10), _SQUARE)},
		{id = &"fake_square", rect = Rect2i(Vector2i(12, 10), _SQUARE)},
	]
	var exported: MapImageExporter = MapImageExporter.export_parts(
		terrain, [] as Array[Dictionary], touching, [] as Array[Vector2i], _params
	)
	assert_true(exported.is_valid(), "\n".join(exported.errors))
	assert_true(_notes_mention(exported, "structures removed"), "\n".join(exported.notes))
	assert_true(MapImageImporter.import_layers(exported.layers(), _params).is_valid())


## The levels come from the map's own terraces, not from the Level step field: a map built at
## one step exports as drawn while the field says another (Alex, 2026-10-23 — the field once
## turned every boundary of a 1.8 map into a cliff).
func test_a_map_built_at_another_step_exports_as_drawn() -> void:
	_params.level_step = _OTHER_STEP
	var layers: MapImageLayers = _drawing(1)
	_paint(layers, MapImagePalette.Meaning.LEVEL_2, Rect2i(_MIDDLE, 0, 100, 100))
	_paint(layers, MapImagePalette.Meaning.LEVEL_3, Rect2i(_MIDDLE, 0, 100, 6))
	var imported: MapImageImporter = MapImageImporter.import_layers(layers, _params)
	_params.level_step = MapGenerationParams.LEVEL_STEP
	var exported: MapImageExporter = _export(imported.map)
	_assert_same_layer(exported, layers, MapImagePalette.Layer.TERRAIN)


## Terraces are numbered in order, so a drop of two steps comes back as one level — with its cliff,
## since the map is steep there — and the relief across it is the importer's one step.
func test_a_gap_between_terraces_is_not_kept() -> void:
	var layers: MapImageLayers = _drawing(1)
	_paint(layers, MapImagePalette.Meaning.LEVEL_3, Rect2i(_MIDDLE, 0, 100, 100))
	_paint(layers, MapImagePalette.Meaning.CLIFF, Rect2i(_MIDDLE - 1, 0, 1, 100))
	var exported: MapImageExporter = _round_trip(layers)
	var east := Vector2i(_MIDDLE + 4, _MIDDLE)
	assert_eq(
		_meaning_at(exported, MapImagePalette.Layer.TERRAIN, east), MapImagePalette.Meaning.LEVEL_2
	)
	assert_eq(
		_meaning_at(exported, MapImagePalette.Layer.CLIFFS, Vector2i(_MIDDLE - 1, _MIDDLE)),
		MapImagePalette.Meaning.CLIFF
	)


## A step the map grades into a walkable slope is drawn with no cliff, so the import grades it too.
func test_a_walkable_step_gets_no_cliff() -> void:
	_params.smoothing_radius = 2
	var layers: MapImageLayers = _drawing(1)
	_paint(layers, MapImagePalette.Meaning.LEVEL_2, Rect2i(_MIDDLE, 0, 100, 100))
	var cliffs: Image = _round_trip(layers).images[MapImagePalette.Layer.CLIFFS]
	assert_true(cliffs.is_invisible(), "no cliff on a graded step")


func test_terraces_past_the_sixth_are_drawn_as_the_sixth_and_listed() -> void:
	var layers: MapImageLayers = _drawing(1)
	for level: int in range(2, MapImagePalette.LEVEL_COUNT + 1):
		_paint(
			layers,
			MapImagePalette.Meaning.LEVEL_1 + level - 1,
			Rect2i((level - 1) * _BAND, 0, 100, 100)
		)
	var imported: MapImageImporter = MapImageImporter.import_layers(layers, _params)
	assert_true(imported.is_valid(), "\n".join(imported.errors))
	# A seventh terrace: a block of a middle band raised above the top one.
	var terrain: TerrainData = imported.map.terrain
	var corners_wide: int = terrain.grid_width() + 1
	for z: int in range(_SEVENTH.position.y, _SEVENTH.end.y + 1):
		for x: int in range(_SEVENTH.position.x, _SEVENTH.end.x + 1):
			terrain.heights[z * corners_wide + x] += _SEVENTH_RISE
	var exported: MapImageExporter = _export(imported.map)
	assert_true(_notes_mention(exported, "terraces"), "\n".join(exported.notes))
	assert_eq(
		_meaning_at(exported, MapImagePalette.Layer.TERRAIN, _SEVENTH.get_center()),
		MapImagePalette.Meaning.LEVEL_6
	)
#endregion
