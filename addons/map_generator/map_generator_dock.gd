@tool
extends VBoxContainer

## The map-generation dock: set the parameters and a seed, generate into the Scenario you have
## open, inspect it, re-roll, and save a keeper as a map scene.
##
## **Generation edits the OPEN SCENE** (Alex, 2026-09-20): the new Map becomes the Scenario's
## `Map` child, which is how every Scenario finds its map. A Scenario that already has one is
## warned about first — generating replaces that map, and an unsaved one is gone.
##
## **Save writes the MAP, not the scenario.** A map scene — terrain, resources, water and start
## points — is the reusable thing; a scenario instances it and supplies its own player slots,
## lighting and triggers.
##
## The parameter form is built from MapGenerationParams' own script properties, grouped by its
## PROPERTY_GROUPS, so a new knob appears here without touching this file. Properties that are
## facts about pieces are hidden: GeneratedMapWriter reads them from the piece scenes and would
## overwrite any edit.

#region Constants
const SAVE_DIR: String = "res://scenes/map"
## Where a saved map's terrain resource goes, beside its scene.
const DEFAULT_MAP_NAME: String = "generated_%d.tscn"
const TERRAIN_SUFFIX: String = "_terrain.tres"
## Terrain for a map generated into a scene that has never been saved.
const SCRATCH_TERRAIN_PATH: String = "res://scenes/scenarios/generated/unsaved_map_terrain.tres"
const NO_SCENARIO_MESSAGE: String = ("Open a Scenario scene first: a generated map becomes its "
	+ "Map child, and a map only plays inside a Scenario.")
const REPLACE_WARNING: String = ("%s already has a Map. Generating replaces it, and an "
	+ "unsaved map is gone — save it as a map scene first if you want to keep it.")
## Properties the form does not offer: piece facts, and the alliance count, which has its own
## field because changing it resets the defaults that depend on it.
const HIDDEN_PROPERTIES: Array[StringName] = [
	&"alliance_count", &"site_energy_per_second", &"pond_rate_multiplier",
]
const MIN_ALLIANCES: int = 2
const MAX_ALLIANCES: int = 8
const MAX_SEED: int = 2147483647
## Step for float fields: fine enough for the occupancy fractions, the smallest knobs there are.
const FLOAT_STEP: float = 0.0001
const REPORT_MIN_HEIGHT_PX: float = 240.0
const WARNING_COLOR := Color(1.0, 0.75, 0.3)
const GROUP_COLOR := Color(0.6, 0.8, 1.0)
#endregion

#region Properties
var _writer := GeneratedMapWriter.new()
var _params: MapGenerationParams
## The last generated map, or null before the first generation. Save writes this one.
var _map: GeneratedMap = null

var _alliances: SpinBox
var _seed: SpinBox
var _form: GridContainer
var _report: TextEdit
## MapGenerationParams.warnings() for the current values, refreshed on every edit.
var _warnings: Label
var _save_button: Button
var _save_dialog: EditorFileDialog
var _replace_dialog: ConfirmationDialog
#endregion


func _ready() -> void:
	_build_controls()
	_reset_params(MIN_ALLIANCES)


#region Building
func _build_controls() -> void:
	var header := GridContainer.new()
	header.columns = 2
	add_child(header)
	_alliances = _spin_box(MIN_ALLIANCES, MAX_ALLIANCES, 1.0)
	_alliances.value_changed.connect(func(value: float) -> void: _reset_params(int(value)))
	_labelled(header, "Alliances", _alliances)
	_seed = _spin_box(0, MAX_SEED, 1.0)
	_labelled(header, "Seed", _seed)

	var buttons := HBoxContainer.new()
	add_child(buttons)
	_button(buttons, "Generate", _generate)
	_button(buttons, "Re-roll", _reroll)
	_save_button = _button(buttons, "Save map as scene…", _ask_save_path)
	_save_button.disabled = true

	_warnings = Label.new()
	_warnings.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_warnings.add_theme_color_override(&"font_color", WARNING_COLOR)
	add_child(_warnings)

	_report = TextEdit.new()
	_report.editable = false
	_report.custom_minimum_size.y = REPORT_MIN_HEIGHT_PX
	_report.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_report.placeholder_text = "Generate a map to see its balance report."
	add_child(_report)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_form = GridContainer.new()
	_form.columns = 2
	_form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_form)


## Defaults for `a_alliances`, with the form rebuilt to show them.
func _reset_params(a_alliances: int) -> void:
	_params = _writer.default_params(a_alliances)
	for child: Node in _form.get_children():
		child.queue_free()
	var by_name: Dictionary = {}
	for property: Dictionary in _params.get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE \
				and not HIDDEN_PROPERTIES.has(StringName(property.name)):
			by_name[String(property.name)] = property
	for group: Dictionary in MapGenerationParams.PROPERTY_GROUPS:
		var shown: Array[Dictionary] = []
		for property_name: String in group.properties:
			if by_name.has(property_name):
				shown.append(by_name[property_name])
				by_name.erase(property_name)
		_add_group(group.name, shown)
	# Anything the groups do not name still shows, rather than going quietly missing.
	var leftovers: Array[Dictionary] = []
	for property_name: String in by_name:
		leftovers.append(by_name[property_name])
	_add_group("Other", leftovers)
	_refresh_warnings()


## One titled section of the form, skipped when nothing in it has an editor.
func _add_group(a_title: String, a_properties: Array[Dictionary]) -> void:
	var fields: Array[Control] = []
	var labels: Array[String] = []
	for property: Dictionary in a_properties:
		var editor: Control = _field_for(property)
		if editor != null:
			fields.append(editor)
			labels.append(String(property.name).capitalize())
	if fields.is_empty():
		return
	var heading := Label.new()
	heading.text = a_title
	heading.add_theme_color_override(&"font_color", GROUP_COLOR)
	_form.add_child(heading)
	_form.add_child(Control.new())  # the grid is two columns wide; a heading spans one row
	for i: int in fields.size():
		_labelled(_form, labels[i], fields[i])


## An editor for one int, float, enum or bool property, bound to _params; null for anything
## else. An enum-typed parameter reports its names in the property's hint, so it gets a menu of
## them rather than a number nobody can read.
func _field_for(a_property: Dictionary) -> Control:
	var property_name: StringName = a_property.name
	if a_property.type == TYPE_INT and a_property.hint == PROPERTY_HINT_ENUM:
		return _enum_field(property_name, String(a_property.hint_string))
	match a_property.type:
		TYPE_BOOL:
			var check := CheckBox.new()
			check.button_pressed = _params.get(property_name)
			check.toggled.connect(func(on: bool) -> void:
				_params.set(property_name, on)
				_refresh_warnings())
			return check
		TYPE_INT, TYPE_FLOAT:
			var is_float: bool = a_property.type == TYPE_FLOAT
			var spin: SpinBox = _spin_box(0, 0, FLOAT_STEP if is_float else 1.0)
			spin.allow_greater = true
			spin.allow_lesser = true
			spin.value = _params.get(property_name)
			spin.value_changed.connect(func(value: float) -> void:
				_params.set(property_name, value if is_float else int(value))
				_refresh_warnings())
			return spin
	return null


## A menu over one enum property. `a_hint` is Godot's "Name:value,Name:value" listing, which is
## also the order the enum declares — the passes read in the order they run.
func _enum_field(a_property: StringName, a_hint: String) -> Control:
	var menu := OptionButton.new()
	menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var current: int = _params.get(a_property)
	for entry: String in a_hint.split(",", false):
		var parts: PackedStringArray = entry.split(":")
		var value: int = int(parts[1]) if parts.size() > 1 else menu.item_count
		menu.add_item(parts[0])
		menu.set_item_id(menu.item_count - 1, value)
		if value == current:
			menu.select(menu.item_count - 1)
	menu.item_selected.connect(func(index: int) -> void:
		_params.set(a_property, menu.get_item_id(index))
		_refresh_warnings())
	return menu


func _refresh_warnings() -> void:
	_warnings.text = "\n".join(_params.warnings())
	_warnings.visible = not _warnings.text.is_empty()


func _spin_box(a_min: int, a_max: int, a_step: float) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = a_min
	spin.max_value = a_max
	spin.step = a_step
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return spin


func _labelled(a_grid: GridContainer, a_text: String, a_editor: Control) -> void:
	var label := Label.new()
	label.text = a_text
	a_grid.add_child(label)
	a_grid.add_child(a_editor)


func _button(a_parent: Container, a_text: String, a_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = a_text
	button.pressed.connect(a_pressed)
	a_parent.add_child(button)
	return button
#endregion


#region Actions
## Generate from the current parameters and seed into the open Scenario. Asks first when that
## Scenario already holds a map, since generating replaces it.
func _generate() -> void:
	var scenario: Node = _open_scenario()
	if scenario == null:
		_report.text = NO_SCENARIO_MESSAGE
		_save_button.disabled = true
		return
	var held: Map = _map_of(scenario)
	if held == null:
		_generate_into(scenario)
		return
	if _replace_dialog == null:
		_replace_dialog = ConfirmationDialog.new()
		_replace_dialog.title = "Replace this Scenario's map?"
		_replace_dialog.confirmed.connect(func() -> void: _generate_into(_open_scenario()))
		add_child(_replace_dialog)
	_replace_dialog.dialog_text = REPLACE_WARNING % scenario.name
	_replace_dialog.popup_centered()


## Generate and hand the map to `a_scenario`, replacing whatever map it holds.
func _generate_into(a_scenario: Node) -> void:
	if a_scenario == null:
		return
	_map = MapGenerator.generate(_params, int(_seed.value))
	_report.text = "\n".join(GeneratedMapWriter.report(_map, "generated"))
	_save_button.disabled = not _map.is_valid()
	if not _map.is_valid():
		return
	var terrain_path: String = _terrain_path_for(a_scenario)
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(terrain_path.get_base_dir()))
	var built: Map = _writer.build_map(_map, terrain_path)
	if built == null:
		push_error("Map Generator: could not write %s" % terrain_path)
		return
	var held: Map = _map_of(a_scenario)
	if held != null:
		a_scenario.remove_child(held)
		held.queue_free()
	GeneratedMapWriter.adopt(a_scenario, built)
	EditorInterface.mark_scene_as_unsaved()
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(built)


func _reroll() -> void:
	_seed.set_value_no_signal(randi() % MAX_SEED)
	_generate()


## The Scenario being edited, or null when the open scene is not one. A map only means
## something inside a Scenario: that is the node that plays it.
func _open_scenario() -> Node:
	var root: Node = EditorInterface.get_edited_scene_root()
	return root if root is Scenario else null


static func _map_of(a_scenario: Node) -> Map:
	for child: Node in a_scenario.get_children():
		if child is Map:
			return child as Map
	return null


## An unsaved scene has no path to put a terrain resource beside, so its terrain goes to the
## scratch folder until the map is saved, which writes it again beside the map scene.
static func _terrain_path_for(a_scenario: Node) -> String:
	var scene_path: String = a_scenario.scene_file_path
	if scene_path.is_empty():
		return SCRATCH_TERRAIN_PATH
	return scene_path.get_basename() + "_map_terrain.tres"


## The dialog is made on first use: an EditorFileDialog exists only inside the editor, and
## building it with the dock would fail wherever the dock is built outside one.
func _ask_save_path() -> void:
	if _save_dialog == null:
		_save_dialog = EditorFileDialog.new()
		_save_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
		_save_dialog.add_filter("*.tscn", "Map scene")
		_save_dialog.file_selected.connect(_save_to)
		add_child(_save_dialog)
	_save_dialog.current_dir = SAVE_DIR
	_save_dialog.current_file = DEFAULT_MAP_NAME % _map.generation_seed
	_save_dialog.popup_file_dialog()


## Write the open Scenario's map — as the author has it, hand edits included — to `a_path`,
## with its terrain beside it.
func _save_to(a_path: String) -> void:
	var scenario: Node = _open_scenario()
	var held: Map = _map_of(scenario) if scenario != null else null
	if held == null:
		_report.text = NO_SCENARIO_MESSAGE
		return
	# Duplicated first: the scene still refers to the terrain written beside it, and a save
	# takes the resource's path over.
	held.terrain_data = held.terrain_data.duplicate() as TerrainData
	if ResourceSaver.save(held.terrain_data, a_path.get_basename() + TERRAIN_SUFFIX) != OK \
			or GeneratedMapWriter.pack(held, a_path) != OK:
		push_error("Map Generator: could not write %s" % a_path)
		return
	EditorInterface.get_resource_filesystem().scan()


#endregion
