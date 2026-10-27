@tool
extends VBoxContainer

## The map-generation dock: set the parameters and a seed, generate into the Scenario you have
## open, inspect it, re-roll, and save a keeper as a map scene. Its second tab imports a
## palette-coded drawing instead (map_image_mode.gd), with the same install, warning and save.
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
const NO_SCENARIO_MESSAGE: String = (
	"Open a Scenario scene first: a generated map becomes its "
	+ "Map child, and a map only plays inside a Scenario."
)
const REPLACE_WARNING: String = (
	"%s already has a Map. Generating replaces it, and an "
	+ "unsaved map is gone — save it as a map scene first if you want to keep it."
)
## Properties the form does not offer: piece facts, and the alliance count, which has its own
## field because changing it resets the defaults that depend on it.
const HIDDEN_PROPERTIES: Array[StringName] = [
	&"alliance_count",
	&"site_energy_per_second",
	&"pond_rate_multiplier",
]
const STALE_WARNING: String = (
	"The generation parameters changed on disk since this form was "
	+ "built. Generate resets it to the new defaults first."
)
const STALE_RESET_NOTICE: String = (
	"The generation parameters changed on disk, so the form was "
	+ "reset to the new defaults; any edits made to it before then are gone."
)
const MIN_ALLIANCES: int = 2
const MAX_ALLIANCES: int = 8
const MAX_SEED: int = 2147483647
const MapImageMode := preload("res://addons/map_generator/map_image_mode.gd")
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
## What the replace dialog does once confirmed: generate, or install an import.
var _on_replace_confirmed: Callable = Callable()
## The default file name the save dialog offers.
var _save_name: String = ""
## The image-import tab.
var _image_mode: Control
## The Scenario an action works on: the open scene in the editor. Replaceable so a test can hand
## the dock a Scenario of its own, since a headless run has no edited scene.
var scenario_source: Callable = _open_scenario
#endregion


func _ready() -> void:
	_build_controls()
	_reset_params(MIN_ALLIANCES)


#region Building
func _build_controls() -> void:
	var modes := TabContainer.new()
	modes.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(modes)
	var page := VBoxContainer.new()
	page.name = "Generate"
	modes.add_child(page)
	_image_mode = MapImageMode.new(self)
	_image_mode.name = "From image"
	modes.add_child(_image_mode)

	var header := GridContainer.new()
	header.columns = 2
	page.add_child(header)
	_alliances = _spin_box(MIN_ALLIANCES, MAX_ALLIANCES, 1.0)
	_alliances.value_changed.connect(func(value: float) -> void: _reset_params(int(value)))
	_labelled(
		header, "Alliances", _alliances, MapGenerationParams.DESCRIPTIONS.get("alliance_count", "")
	)
	_seed = _spin_box(0, MAX_SEED, 1.0)
	_labelled(
		header,
		"Seed",
		_seed,
		"The random seed. The same seed and parameters always make the same map."
	)

	var buttons := HBoxContainer.new()
	page.add_child(buttons)
	_button(buttons, "Generate", _generate)
	_button(buttons, "Re-roll", _reroll)
	_save_button = _button(buttons, "Save map as scene…", _ask_save_path)
	_save_button.disabled = true

	_warnings = Label.new()
	_warnings.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_warnings.add_theme_color_override(&"font_color", WARNING_COLOR)
	page.add_child(_warnings)

	_report = TextEdit.new()
	_report.editable = false
	_report.custom_minimum_size.y = REPORT_MIN_HEIGHT_PX
	_report.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_report.placeholder_text = "Generate a map to see its balance report."
	page.add_child(_report)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
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
		if (
			property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE
			and not HIDDEN_PROPERTIES.has(StringName(property.name))
		):
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
	var tooltips: Array[String] = []
	for property: Dictionary in a_properties:
		var editor: Control = _field_for(property)
		if editor != null:
			fields.append(editor)
			labels.append(String(property.name).capitalize())
			tooltips.append(MapGenerationParams.DESCRIPTIONS.get(String(property.name), ""))
	if fields.is_empty():
		return
	var heading := Label.new()
	heading.text = a_title
	heading.add_theme_color_override(&"font_color", GROUP_COLOR)
	_form.add_child(heading)
	_form.add_child(Control.new())  # the grid is two columns wide; a heading spans one row
	for i: int in fields.size():
		_labelled(_form, labels[i], fields[i], tooltips[i])


## An editor for one int, float, enum, bool or Vector2i property, bound to _params; null for
## anything else. An enum-typed parameter reports its names in the property's hint, so it gets a
## menu of them rather than a number nobody can read.
func _field_for(a_property: Dictionary) -> Control:
	var property_name: StringName = a_property.name
	if a_property.type == TYPE_INT and a_property.hint == PROPERTY_HINT_ENUM:
		return _enum_field(property_name, String(a_property.hint_string))
	match a_property.type:
		TYPE_BOOL:
			var check := CheckBox.new()
			check.button_pressed = _params.get(property_name)
			check.toggled.connect(
				func(on: bool) -> void:
					_params.set(property_name, on)
					_refresh_warnings()
			)
			return check
		TYPE_INT, TYPE_FLOAT:
			var is_float: bool = a_property.type == TYPE_FLOAT
			var spin: SpinBox = _spin_box(0, 0, FLOAT_STEP if is_float else 1.0)
			spin.allow_greater = true
			spin.allow_lesser = true
			spin.value = _params.get(property_name)
			spin.value_changed.connect(
				func(value: float) -> void:
					_params.set(property_name, value if is_float else int(value))
					_refresh_warnings()
			)
			return spin
		TYPE_VECTOR2I:
			return _vector2i_field(property_name)
	return null


## Two whole-number boxes side by side, x then y, editing one Vector2i property.
func _vector2i_field(a_property: StringName) -> Control:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var current: Vector2i = _params.get(a_property)
	for axis: int in 2:
		var spin: SpinBox = _spin_box(0, 0, 1.0)
		spin.allow_greater = true
		spin.allow_lesser = true
		spin.value = current[axis]
		spin.value_changed.connect(
			func(value: float) -> void:
				var vector: Vector2i = _params.get(a_property)
				vector[axis] = int(value)
				_params.set(a_property, vector)
				_refresh_warnings()
		)
		row.add_child(spin)
	return row


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
	menu.item_selected.connect(
		func(index: int) -> void:
			_params.set(a_property, menu.get_item_id(index))
			_refresh_warnings()
	)
	return menu


func _refresh_warnings() -> void:
	_warnings.text = STALE_WARNING if _params_are_stale() else "\n".join(_params.warnings())
	_warnings.visible = not _warnings.text.is_empty()


## True when MapGenerationParams was reloaded since _params was built. A hot-reloaded @tool
## instance gets null for a member the new script added, not its initializer, so a renamed or
## new knob reads as nothing: a renamed energy budget once generated maps with no resources.
func _params_are_stale() -> bool:
	var fresh := MapGenerationParams.new()
	for property: Dictionary in fresh.get_property_list():
		if (
			property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE
			and typeof(_params.get(property.name)) != typeof(fresh.get(property.name))
		):
			return true
	return false


func _spin_box(a_min: int, a_max: int, a_step: float) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = a_min
	spin.max_value = a_max
	spin.step = a_step
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return spin


## A label and its editor, both showing `a_tooltip` on hover. A Label ignores the mouse by
## default, so it is set to take it — the name is where a reader points.
func _labelled(
	a_grid: GridContainer, a_text: String, a_editor: Control, a_tooltip: String = ""
) -> void:
	var label := Label.new()
	label.text = a_text
	if not a_tooltip.is_empty():
		label.tooltip_text = a_tooltip
		label.mouse_filter = Control.MOUSE_FILTER_STOP
		a_editor.tooltip_text = a_tooltip
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
	var scenario: Node = scenario_source.call()
	if scenario == null:
		_report.text = NO_SCENARIO_MESSAGE
		_save_button.disabled = true
		return
	confirm_replace(
		scenario,
		REPLACE_WARNING % scenario.name,
		func() -> void: _generate_into(scenario_source.call())
	)


## Run `a_then` at once when `a_scenario` holds no map, or once the author confirms replacing
## it, warned with `a_warning`.
func confirm_replace(a_scenario: Node, a_warning: String, a_then: Callable) -> void:
	if map_of(a_scenario) == null:
		a_then.call()
		return
	if _replace_dialog == null:
		_replace_dialog = ConfirmationDialog.new()
		_replace_dialog.title = "Replace this Scenario's map?"
		_replace_dialog.confirmed.connect(func() -> void: _on_replace_confirmed.call())
		add_child(_replace_dialog)
	_on_replace_confirmed = a_then
	_replace_dialog.dialog_text = a_warning
	_replace_dialog.popup_centered()


## Generate and hand the map to `a_scenario`, replacing whatever map it holds.
func _generate_into(a_scenario: Node) -> void:
	if a_scenario == null:
		return
	var was_stale: bool = _params_are_stale()
	if was_stale:
		_reset_params(int(_alliances.value))
	_map = MapGenerator.generate(_params, int(_seed.value))
	_report.text = "\n".join(GeneratedMapWriter.report(_map, "generated"))
	if was_stale:
		_report.text = STALE_RESET_NOTICE + "\n\n" + _report.text
	_save_button.disabled = not _map.is_valid()
	if not _map.is_valid():
		return
	var built: Map = build_for(a_scenario, _map)
	if built == null:
		return
	var held: Map = detach_map(a_scenario)
	if held != null:
		held.queue_free()
	install(a_scenario, built)
	_save_name = DEFAULT_MAP_NAME % _map.generation_seed


## `a_map` built as a Map node, its terrain written where `a_scenario`'s map terrain goes; null,
## with the error pushed, when it could not be written.
func build_for(a_scenario: Node, a_map: GeneratedMap) -> Map:
	var terrain_path: String = _terrain_path_for(a_scenario)
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(terrain_path.get_base_dir())
	)
	var built: Map = _writer.build_map(a_map, terrain_path)
	if built == null:
		push_error("Map Generator: could not write %s" % terrain_path)
	return built


## Default generation parameters with every piece fact read from the piece scenes: what an
## image import matches its structures against.
func piece_facts() -> MapGenerationParams:
	return _writer.default_params(MIN_ALLIANCES)


## Take `a_scenario`'s map out of it, unfreed, or null when it has none.
static func detach_map(a_scenario: Node) -> Map:
	var held: Map = map_of(a_scenario)
	if held != null:
		a_scenario.remove_child(held)
	return held


## Hand `a_built` to `a_scenario` as its map, leaving the scene unsaved with the map selected.
func install(a_scenario: Node, a_built: Map) -> void:
	GeneratedMapWriter.adopt(a_scenario, a_built)
	if Engine.is_editor_hint():
		EditorInterface.mark_scene_as_unsaved()
		EditorInterface.get_selection().clear()
		EditorInterface.get_selection().add_node(a_built)


func _reroll() -> void:
	_seed.set_value_no_signal(randi() % MAX_SEED)
	_generate()


## The Scenario being edited, or null when the open scene is not one. A map only means
## something inside a Scenario: that is the node that plays it.
func _open_scenario() -> Node:
	var root: Node = EditorInterface.get_edited_scene_root()
	return root if root is Scenario else null


static func map_of(a_scenario: Node) -> Map:
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
	ask_save_path(_save_name)


## Ask where to save the open Scenario's map, offering `a_default_name`.
func ask_save_path(a_default_name: String) -> void:
	if _save_dialog == null:
		_save_dialog = EditorFileDialog.new()
		_save_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
		_save_dialog.add_filter("*.tscn", "Map scene")
		_save_dialog.file_selected.connect(_save_to)
		add_child(_save_dialog)
	_save_dialog.current_dir = SAVE_DIR
	_save_dialog.current_file = a_default_name
	_save_dialog.popup_file_dialog()


## Write the open Scenario's map — as the author has it, hand edits included — to `a_path`,
## with its terrain beside it.
func _save_to(a_path: String) -> void:
	var scenario: Node = scenario_source.call()
	var held: Map = map_of(scenario) if scenario != null else null
	if held == null:
		_report.text = NO_SCENARIO_MESSAGE
		return
	# Duplicated first: the scene still refers to the terrain written beside it, and a save
	# takes the resource's path over.
	held.terrain_data = held.terrain_data.duplicate() as TerrainData
	if (
		ResourceSaver.save(held.terrain_data, a_path.get_basename() + TERRAIN_SUFFIX) != OK
		or GeneratedMapWriter.pack(held, a_path) != OK
	):
		push_error("Map Generator: could not write %s" % a_path)
		return
	EditorInterface.get_resource_filesystem().scan()

#endregion
