extends GutTest

## Tests for the map-generation dock's parameter form (addons/map_generator). The dock's
## actions drive EditorInterface, which a headless run has none of; what is tested is that the
## form is built from MapGenerationParams and edits it.
##
## TODO: nothing covers the actions themselves — generating into the open Scenario, the warning
## before replacing a map it already has, and saving the map as a scene. They need an editor,
## so covering them means either an editor-only test harness or pulling the scene surgery out
## of the dock into something testable (the writer already holds build_map, pack and adopt).
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_MapGeneratorDock.gd \
##     -gdir=res://tests/none -gexit

var _dock: Node


func before_each() -> void:
	_dock = (load("res://addons/map_generator/map_generator_dock.gd") as GDScript).new()
	add_child_autofree(_dock)


## The form's editor for a parameter, found by its label.
func _field(a_property: String) -> Control:
	var form: GridContainer = _dock._form
	var children: Array[Node] = form.get_children()
	for i: int in range(0, children.size() - 1, 2):
		if (children[i] as Label).text == a_property.capitalize():
			return children[i + 1] as Control
	return null


func test_the_form_offers_generation_knobs_but_not_piece_facts() -> void:
	assert_not_null(_field("play_size_min"))
	assert_not_null(_field("building_capacity_per_player"))
	assert_null(_field("site_energy_per_second"))
	assert_null(_field("alliance_count"))


## One box of a two-box Vector2i field: x is 0, y is 1.
func _axis(a_property: String, a_axis: int) -> SpinBox:
	return _field(a_property).get_child(a_axis) as SpinBox


func test_editing_a_field_edits_the_parameters() -> void:
	(_field("building_capacity_per_player") as SpinBox).value = 101
	assert_eq(_dock._params.building_capacity_per_player, 101)
	(_field("cluster_large_building_bias") as SpinBox).value = 0.25
	assert_almost_eq(_dock._params.cluster_large_building_bias, 0.25, 1e-6)


func test_a_vector_field_edits_each_axis_alone() -> void:
	var before: Vector2i = _dock._params.play_size_max
	_axis("play_size_max", 1).value = 133
	assert_eq(_dock._params.play_size_max, Vector2i(before.x, 133))


func test_a_play_size_minimum_above_its_maximum_is_warned() -> void:
	_axis("play_size_min", 0).value = _dock._params.play_size_max.x + 1
	assert_true(_dock._warnings.visible)
	assert_string_contains(_dock._warnings.text, "exceeds the maximum")


func test_changing_the_alliance_count_resets_to_its_defaults() -> void:
	_axis("play_size_max", 0).value = 101
	_dock._alliances.value = 3
	assert_eq(_dock._params.alliance_count, 3)
	assert_ne(_dock._params.play_size_max.x, 101)


func test_a_building_capacity_at_the_failure_point_is_warned() -> void:
	var capacity: SpinBox = _field("building_capacity_per_player") as SpinBox
	capacity.value = MapGenerationParams.BUILDING_CAPACITY_FAILURE - 1
	assert_false(_dock._warnings.visible)
	capacity.value = MapGenerationParams.BUILDING_CAPACITY_FAILURE
	assert_true(_dock._warnings.visible)
	assert_string_contains(_dock._warnings.text, str(MapGenerationParams.BUILDING_CAPACITY_FAILURE))


## Every knob belongs to exactly one group. A new parameter that nobody filed still appears —
## the dock collects leftovers under "Other" — so this is what says it was filed on purpose.
func test_every_parameter_is_in_exactly_one_group() -> void:
	var filed: Dictionary = {}
	for group: Dictionary in MapGenerationParams.PROPERTY_GROUPS:
		for property_name: String in group.properties:
			assert_false(filed.has(property_name), "%s is in two groups" % property_name)
			filed[property_name] = true
	var params := MapGenerationParams.new()
	for property: Dictionary in params.get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			assert_true(
				filed.has(String(property.name)),
				"%s is in no group — file it in PROPERTY_GROUPS" % property.name
			)
			filed.erase(String(property.name))
	assert_eq(filed.keys(), [], "groups name parameters that no longer exist")


## Every knob has hover text, and the form shows it on both the name and the editor.
func test_every_parameter_has_a_description() -> void:
	var params := MapGenerationParams.new()
	for property: Dictionary in params.get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			assert_false(
				String(MapGenerationParams.DESCRIPTIONS.get(String(property.name), "")).is_empty(),
				"%s has no entry in DESCRIPTIONS" % property.name
			)
	for property_name: String in MapGenerationParams.DESCRIPTIONS:
		assert_true(
			property_name in params, "DESCRIPTIONS names %s, which does not exist" % property_name
		)


func test_a_field_shows_its_description_on_hover() -> void:
	var expected: String = MapGenerationParams.DESCRIPTIONS["building_capacity_per_player"]
	assert_eq(_field("building_capacity_per_player").tooltip_text, expected)
	var form: Array[Node] = _dock._form.get_children()
	var label: Label = form[form.find(_field("building_capacity_per_player")) - 1] as Label
	assert_eq(label.tooltip_text, expected)
	assert_eq(label.mouse_filter, Control.MOUSE_FILTER_STOP, "a Label ignores the mouse by default")


func test_the_form_is_sectioned_by_group() -> void:
	var headings: Array[String] = []
	for child: Node in _dock._form.get_children():
		if (
			child is Label
			and MapGenerationParams.PROPERTY_GROUPS.any(
				func(group: Dictionary) -> bool: return group.name == (child as Label).text
			)
		):
			headings.append((child as Label).text)
	assert_has(headings, "Elevation")
	assert_has(headings, "Ponds")
	assert_does_not_have(headings, "Alliances", "its field is the header spin box, not the form")


## A pass is chosen by name, not by number: "Terrain", not 5.
func test_the_last_pass_is_chosen_from_named_passes() -> void:
	var menu: OptionButton = _field("last_pass") as OptionButton
	assert_not_null(menu, "last_pass is an enum, so the form gives it a menu")
	assert_eq(menu.item_count, MapGenerationParams.Pass.size())
	assert_eq(menu.get_item_text(0), "Extent")
	assert_eq(
		menu.get_item_id(menu.selected),
		int(MapGenerationParams.Pass.VISUALS),
		"the default runs every pass"
	)
	menu.item_selected.emit(menu.get_item_index(MapGenerationParams.Pass.TOPOLOGY))
	assert_eq(_dock._params.last_pass, MapGenerationParams.Pass.TOPOLOGY)
	assert_string_contains(_dock._warnings.text, "topology")


#region Image mode
## The image tab, driven against a stand-in Scenario: a headless run has no edited scene, so the
## dock's scenario_source is pointed at one built here. The drawing is a synthetic flat diamond
## written as an OpenRaster file, so no shipped content is read but the piece facts.
const _IMAGE_PATH: String = "user://test_dock_image.ora"
const _IMAGE_PLAY := Vector2i(10, 10)
const _EXPORT_PATH: String = "user://test_dock_export.ora"
## A docked panel at about its narrowest in the editor's default layout.
const _DOCKED_PANEL_PX: float = 300.0
## A readout picture and the canvas it is drawn on: ten screen pixels a cell.
const _READOUT_CELLS: int = 10
const _READOUT_PX: float = 100.0


## Kept OUT of the tree: a Map entering one outside the editor builds its runtime navmesh, whose
## deferred rebuilds would outlive the test and fail whichever test runs next.
func _image_scenario() -> Node3D:
	var scenario: Node3D = autofree(Node3D.new())
	scenario.name = "Scenario"
	_dock.scenario_source = func() -> Node: return scenario
	return scenario


## A flat level-2 diamond with one deep pond, or with a stray colour when `a_broken`, and a
## shelter at `a_shelter` (its footprint's origin) when that is not negative.
func _write_drawing(a_broken: bool = false, a_shelter := Vector2i(-1, -1)) -> void:
	var probe := TerrainData.new()
	probe.play_size = _IMAGE_PLAY
	var side: int = probe.grid_width()
	var terrain := Image.create_empty(side, side, false, Image.FORMAT_RGBA8)
	var water := Image.create_empty(side, side, false, Image.FORMAT_RGBA8)
	for z: int in side:
		for x: int in side:
			var is_in: bool = probe.is_cell_in_play(Vector2i(x, z))
			terrain.set_pixel(x, z, Color8(0xC8, 0xCE, 0x8C) if is_in else Color8(0x3C, 0x3C, 0x46))
			if absi(x - side / 2) <= 2 and absi(z - side / 2) <= 2:
				water.set_pixel(x, z, Color8(0x7C, 0x8B, 0xC8))
	if a_broken:
		terrain.set_pixel(side / 2, side / 2, Color8(1, 2, 3))
	var named: Array[Dictionary] = [
		{name = "water", image = water}, {name = "terrain", image = terrain}
	]
	if a_shelter.x >= 0:
		var structures := Image.create_empty(side, side, false, Image.FORMAT_RGBA8)
		var footprint: Vector2i = _dock.piece_facts().shelter_piece.footprint
		structures.fill_rect(Rect2i(a_shelter, footprint), Color8(0xFF, 0x00, 0xFF))
		named.insert(0, {name = "structures", image = structures})
	assert_eq(OpenRaster.write(_IMAGE_PATH, Vector2i(side, side), named), OK)


## Nothing on the image tab may widen it past a docked panel: a row of buttons once did, and
## pushed the Browse button off the panel's edge, leaving the path a bare text field.
func test_the_image_tab_fits_a_docked_panel() -> void:
	var width: float = _dock._image_mode.get_combined_minimum_size().x
	assert_lte(width, _DOCKED_PANEL_PX, "the image tab's narrowest width")


## The readout draws a cell as a whole number of screen pixels and names the cell under the
## pointer: on a 100-pixel canvas a 10-cell picture is ten pixels a cell.
func test_the_readout_names_the_cell_under_the_pointer() -> void:
	var readout: Node = _dock._image_mode._readout
	var image := Image.create_empty(_READOUT_CELLS, _READOUT_CELLS, false, Image.FORMAT_RGBA8)
	readout.show_image(image, func(cell: Vector2i) -> String: return "cell %s" % cell)
	var canvas: Control = readout._canvas
	canvas.size = Vector2.ONE * _READOUT_PX
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(55.0, 25.0)
	canvas._gui_input(motion)
	assert_eq(readout._info.text, "cell (5, 2)")
	assert_eq(canvas.drawn_rect(), Rect2(Vector2.ZERO, Vector2.ONE * _READOUT_PX))


func test_the_readout_scrolls_with_the_palette() -> void:
	var readout: Node = _dock._image_mode._readout
	var palette: Node = _dock._image_mode.find_child("Palette", true, false)
	assert_eq(readout.get_parent(), palette.get_parent(), "one column, one scroll")
	assert_true(readout.get_parent().get_parent() is ScrollContainer)


func test_the_image_tab_lists_every_palette_colour() -> void:
	var view: VBoxContainer = _dock._image_mode.palette_view()
	var swatches: int = view.find_children("*", "ColorRect", true, false).size()
	assert_eq(swatches, MapImagePalette.ENTRIES.size())
	var texts: Array[Node] = view.find_children("*", "RichTextLabel", true, false)
	assert_eq(texts.size(), swatches, "one text per colour")
	assert_true(
		texts.all(func(text: RichTextLabel) -> bool: return text.selection_enabled),
		"every colour's text can be selected and copied"
	)
	view.free()


func test_importing_a_drawing_installs_a_tagged_map() -> void:
	var scenario: Node3D = _image_scenario()
	_write_drawing()
	_dock._image_mode.set_drawing_path(_IMAGE_PATH)
	_dock._image_mode.import_drawing()
	var map: Map = _dock.map_of(scenario)
	assert_not_null(map, _dock._image_mode.report_text())
	assert_eq(map.terrain_data.play_size, _IMAGE_PLAY)
	var waters: Array = map.get_children().filter(func(n: Node) -> bool: return n is WaterBody)
	assert_eq(waters.size(), 1, _dock._image_mode.report_text())
	assert_true(MapImageReimport.is_imported(waters[0]))
	assert_false(MapImageReimport.is_imported(map.get_node("NavigationRegion")))


func test_a_failed_import_leaves_the_scenario_alone() -> void:
	var scenario: Node3D = _image_scenario()
	_write_drawing(true)
	_dock._image_mode.set_drawing_path(_IMAGE_PATH)
	_dock._image_mode.import_drawing()
	assert_null(_dock.map_of(scenario))
	assert_string_contains(_dock._image_mode.report_text(), "FAILED")
	assert_string_contains(_dock._image_mode.report_text(), "#010203")
	# The readout names the issue under the pointer: here, the stray pixel at the middle.
	var result: MapImageImporter = _dock._image_mode.last_import
	# Refused for its colour, before the grid was fitted: the readout is the drawing itself.
	var middle: Vector2i = result.layers.size / 2
	assert_not_null(_dock._image_mode._readout.texture(), "a refused drawing still has a readout")
	assert_string_contains(_dock._image_mode._describe_import(result, middle), "[1, red]")


func test_a_reimport_keeps_hand_placed_nodes_and_drops_imported_ones() -> void:
	var scenario: Node3D = _image_scenario()
	_write_drawing()
	_dock._image_mode.set_drawing_path(_IMAGE_PATH)
	_dock._image_mode.import_drawing()
	var first: Map = _dock.map_of(scenario)
	var note := Node3D.new()
	note.name = "AuthorsNote"
	first.add_child(note)
	note.owner = scenario
	# A second import replaces a map, so it asks first; confirm it as the author would.
	_dock._image_mode.import_drawing()
	_dock._on_replace_confirmed.call()
	var second: Map = _dock.map_of(scenario)
	assert_ne(second, first)
	assert_eq(second.get_node_or_null("AuthorsNote"), note, "a hand-placed node moves across")
	assert_eq(note.owner, scenario, "and is still saved with the scene")
	var waters: Array = second.get_children().filter(func(n: Node) -> bool: return n is WaterBody)
	assert_eq(waters.size(), 1, "the old import's water is replaced, not doubled")


func test_an_imported_map_exports_to_a_drawing_that_imports_again() -> void:
	_image_scenario()
	_write_drawing()
	_dock._image_mode.set_drawing_path(_IMAGE_PATH)
	_dock._image_mode.import_drawing()
	assert_true(_dock._image_mode.prepare_export(), _dock._image_mode.report_text())
	_dock._image_mode.export_to(_EXPORT_PATH)
	assert_string_contains(_dock._image_mode.report_text(), "sculpting does not survive")
	assert_not_null(
		_dock._image_mode._readout.texture(), "the export shows its passability readout"
	)
	var reimported: MapImageImporter = MapImageImporter.import_path(
		_EXPORT_PATH, _dock._image_mode.params()
	)
	assert_true(reimported.is_valid(), "\n".join(reimported.errors))
	assert_eq(reimported.map.waters.size(), 1)


## The shelter is read back off the placed piece — its position and turn — onto the cells it
## was drawn on.
func test_an_imported_shelter_exports_onto_its_drawn_cells() -> void:
	_image_scenario()
	var origin := Vector2i(5, 9)
	_write_drawing(false, origin)
	_dock._image_mode.set_drawing_path(_IMAGE_PATH)
	_dock._image_mode.import_drawing()
	assert_true(_dock._image_mode.prepare_export(), _dock._image_mode.report_text())
	var exported: MapImageExporter = _dock._image_mode._pending_export
	var structures: Image = exported.images[MapImagePalette.Layer.STRUCTURES]
	var drawn := Rect2i(origin, _dock.piece_facts().shelter_piece.footprint)
	for z: int in exported.size.y:
		for x: int in exported.size.x:
			assert_eq(
				structures.get_pixel(x, z).a8 > 0,
				drawn.has_point(Vector2i(x, z)),
				"shelter cell %s" % Vector2i(x, z)
			)


func test_exporting_with_no_map_says_so_and_writes_nothing() -> void:
	_image_scenario()
	assert_false(_dock._image_mode.prepare_export())
	assert_eq(_dock._image_mode.report_text(), _dock._image_mode.NO_MAP_MESSAGE)
#endregion
