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


func test_editing_a_field_edits_the_parameters() -> void:
	(_field("play_size_max") as SpinBox).value = 101
	assert_eq(_dock._params.play_size_max, 101)
	(_field("cluster_large_building_bias") as SpinBox).value = 0.25
	assert_almost_eq(_dock._params.cluster_large_building_bias, 0.25, 1e-6)


func test_changing_the_alliance_count_resets_to_its_defaults() -> void:
	(_field("play_size_max") as SpinBox).value = 101
	_dock._alliances.value = 3
	assert_eq(_dock._params.alliance_count, 3)
	assert_ne(_dock._params.play_size_max, 101)


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
			assert_true(filed.has(String(property.name)),
				"%s is in no group — file it in PROPERTY_GROUPS" % property.name)
			filed.erase(String(property.name))
	assert_eq(filed.keys(), [], "groups name parameters that no longer exist")


## Every knob has hover text, and the form shows it on both the name and the editor.
func test_every_parameter_has_a_description() -> void:
	var params := MapGenerationParams.new()
	for property: Dictionary in params.get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			assert_false(String(MapGenerationParams.DESCRIPTIONS.get(String(property.name), "")).is_empty(),
				"%s has no entry in DESCRIPTIONS" % property.name)
	for property_name: String in MapGenerationParams.DESCRIPTIONS:
		assert_true(property_name in params, "DESCRIPTIONS names %s, which does not exist" % property_name)


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
		if child is Label and MapGenerationParams.PROPERTY_GROUPS.any(
				func(group: Dictionary) -> bool: return group.name == (child as Label).text):
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
	assert_eq(menu.get_item_id(menu.selected), int(MapGenerationParams.Pass.ELEVATION),
		"the default runs every pass")
	menu.item_selected.emit(menu.get_item_index(MapGenerationParams.Pass.TOPOLOGY))
	assert_eq(_dock._params.last_pass, MapGenerationParams.Pass.TOPOLOGY)
	assert_string_contains(_dock._warnings.text, "topology")
