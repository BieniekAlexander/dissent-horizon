@tool
extends VBoxContainer

## The Map Generator dock's image tab: import a palette-coded drawing into the open Scenario
## (gdd/systems/terrain-and-navigation/map-from-image.md). The dock's own behaviour carries over
## through it: the warning before replacing a map, the unsaved scene, Save map as scene.
##
## A FAILED import changes nothing in the Scenario; its report says why, and the readout marks
## where. A re-import keeps every node on the old map the importer did not put there, and flags
## the hand-placed pieces the new terrain breaks (MapImageReimport).

#region Constants
const MapImageReadout := preload("res://addons/map_generator/map_image_readout.gd")
const FILE_FILTERS: PackedStringArray = [
	"*.ora ; OpenRaster", "*.aseprite, *.ase ; Aseprite", "*.png ; Flat layer PNG (map.terrain.png)"
]
const REPLACE_WARNING: String = (
	"%s already has a Map. Importing replaces its terrain, water, start points and every "
	+ "structure an earlier import placed; pieces placed by hand are kept and checked against "
	+ "the new ground. Hand edits to the terrain itself are gone."
)
const NO_PATH_MESSAGE: String = "Choose a drawing to import first."
const NO_MAP_MESSAGE: String = "The open Scenario has no Map to export."
const EXPORT_FILTER: String = "*.ora ; OpenRaster"
const EXPORT_TITLE: String = "Export map as a drawing — re-importing it replaces sculpted terrain"
const EXPORT_WARNING: String = (
	"Importing this drawing replaces the terrain: sculpting does not survive, and each cell "
	+ "comes back as its nearest level."
)
const PASSAGE_KEY: String = (
	"Readout: where a unit can walk on the map and on the drawing re-imported. Red, a passage "
	+ "the re-import opens; blue, one it closes; pale tints, edges that only moved."
)
const DEFAULT_DRAWING_NAME: String = "%s_drawing.ora"
const DEFAULT_MAP_NAME: String = "%s_map.tscn"
const SWATCH_PX := Vector2(24.0, 16.0)
## The palette's text column at its narrowest; its labels wrap to whatever width it gets.
const MEANING_MIN_PX: float = 120.0
const REPORT_MIN_HEIGHT_PX: float = 200.0
const MAX_SEED: int = 2147483647
const MAX_RADIUS: int = 16
const MAX_LEVEL_STEP: float = 5.0
const LEVEL_STEP_INCREMENT: float = 0.1
const MAX_NOISE_CELLS: float = 16.0
const NOISE_STEP: float = 0.1
const GROUP_COLOR := Color(0.6, 0.8, 1.0)
#endregion

#region Properties
var _dock: Node
var _path: LineEdit
var _level_step: SpinBox
var _radius: SpinBox
var _noise: SpinBox
var _seed: SpinBox
var _report: TextEdit
var _readout: MapImageReadout
var _save_button: Button
var _file_dialog: EditorFileDialog
var _export_dialog: EditorFileDialog
## The export waiting on its file name, or null.
var _pending_export: MapImageExporter = null
var _pending_name: String = ""
## The last import, or null before the first.
var last_import: MapImageImporter = null
#endregion


func _init(a_dock: Node = null) -> void:
	_dock = a_dock


func _ready() -> void:
	_build_controls()


#region Building
func _build_controls() -> void:
	# Browse first, so a dock narrower than the row clips the path's tail, never the button.
	var path_row := HBoxContainer.new()
	add_child(path_row)
	_button(path_row, "Browse…", _browse)
	_path = LineEdit.new()
	_path.placeholder_text = "res://…/map.ora, .aseprite or map.terrain.png"
	_path.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	path_row.add_child(_path)

	var fields := GridContainer.new()
	fields.columns = 2
	add_child(fields)
	var defaults := MapImageImportParams.new()
	_level_step = _spin(
		LEVEL_STEP_INCREMENT, MAX_LEVEL_STEP, LEVEL_STEP_INCREMENT, defaults.level_step
	)
	_labelled(fields, "Level step", _level_step, "level_step")
	_radius = _spin(0, MAX_RADIUS, 1.0, defaults.smoothing_radius)
	_labelled(fields, "Smoothing radius", _radius, "smoothing_radius")
	_noise = _spin(0, MAX_NOISE_CELLS, NOISE_STEP, defaults.edge_noise_cells)
	_labelled(fields, "Edge noise (cells)", _noise, "edge_noise_cells")
	_seed = _spin(0, MAX_SEED, 1.0, defaults.edge_noise_seed)
	_labelled(fields, "Edge noise seed", _seed, "edge_noise_seed")

	# Wraps rather than widening the dock: a row of three buttons was wider than the docked panel
	# and pushed everything the width decides — Browse included — off its right edge.
	var buttons := HFlowContainer.new()
	add_child(buttons)
	_button(buttons, "Import into Scenario", import_drawing)
	_save_button = _button(buttons, "Save map as scene…", _ask_save)
	_save_button.disabled = true
	_button(buttons, "Export map as drawing…", export_map)

	_report = TextEdit.new()
	_report.editable = false
	_report.custom_minimum_size.y = REPORT_MIN_HEIGHT_PX
	_report.placeholder_text = "Import a drawing to see its report."
	add_child(_report)

	# The readout and the palette scroll together, so a readout as wide as the dock never pushes
	# the palette out of reach or squeezes it to a sliver.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var scrolled := VBoxContainer.new()
	scrolled.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(scrolled)
	_readout = MapImageReadout.new()
	scrolled.add_child(_readout)
	scrolled.add_child(palette_view())


## The palette, layer by layer: a swatch, its hex code and its meaning, for every entry in
## MapImagePalette — the importer's own table, so the two cannot disagree.
static func palette_view() -> VBoxContainer:
	var view := VBoxContainer.new()
	view.name = "Palette"
	for layer: int in MapImagePalette.LAYER_NAMES:
		var heading := Label.new()
		heading.text = 'Layer "%s"' % MapImagePalette.LAYER_NAMES[layer]
		heading.add_theme_color_override(&"font_color", GROUP_COLOR)
		view.add_child(heading)
		# A swatch and one wrapping label each, so no colour's text sets the dock's width.
		var grid := GridContainer.new()
		grid.columns = 2
		view.add_child(grid)
		for entry: Dictionary in MapImagePalette.entries_of(layer):
			var swatch := ColorRect.new()
			swatch.color = entry.color
			swatch.custom_minimum_size = SWATCH_PX
			grid.add_child(swatch)
			# Selectable, so a hex code can be copied into the drawing tool.
			var meaning := RichTextLabel.new()
			meaning.bbcode_enabled = false
			meaning.text = (
				"%s  %s" % [MapImagePalette.hex(entry.color), MapImagePalette.LABELS[entry.meaning]]
			)
			meaning.selection_enabled = true
			meaning.context_menu_enabled = true
			meaning.fit_content = true
			meaning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			meaning.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			meaning.custom_minimum_size.x = MEANING_MIN_PX
			grid.add_child(meaning)
	return view


func _spin(a_min: float, a_max: float, a_step: float, a_value: float) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = a_min
	spin.max_value = a_max
	spin.step = a_step
	spin.value = a_value
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return spin


func _labelled(
	a_grid: GridContainer, a_text: String, a_editor: Control, a_property: String
) -> void:
	var label := Label.new()
	label.text = a_text
	label.tooltip_text = MapImageImportParams.DESCRIPTIONS.get(a_property, "")
	label.mouse_filter = Control.MOUSE_FILTER_STOP
	a_editor.tooltip_text = label.tooltip_text
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
## The dock fields as import parameters, with the generator's piece facts read from the piece
## scenes, so the structures are matched against footprints no one typed.
func params() -> MapImageImportParams:
	var out := MapImageImportParams.new()
	out.level_step = _level_step.value
	out.smoothing_radius = int(_radius.value)
	out.edge_noise_cells = _noise.value
	out.edge_noise_seed = int(_seed.value)
	out.generation = _dock.piece_facts()
	return out


func set_drawing_path(a_path: String) -> void:
	_path.text = a_path


## Import the drawing named in the path field into the open Scenario. Asks first when that
## Scenario already holds a map; a failed import changes nothing.
func import_drawing() -> void:
	var scenario: Node = _dock.scenario_source.call()
	if scenario == null:
		_report.text = _dock.NO_SCENARIO_MESSAGE
		return
	if _path.text.strip_edges().is_empty():
		_report.text = NO_PATH_MESSAGE
		return
	var import_params: MapImageImportParams = params()
	var result: MapImageImporter = MapImageImporter.import_path(
		_path.text.strip_edges(), import_params
	)
	last_import = result
	_show(result, import_params, [] as Array[Vector2i], PackedStringArray())
	_save_button.disabled = true
	if not result.is_valid():
		return
	_dock.confirm_replace(
		scenario,
		REPLACE_WARNING % scenario.name,
		func() -> void: _install(_dock.scenario_source.call(), result, import_params)
	)


func _install(a_scenario: Node, a_result: MapImageImporter, a_params: MapImageImportParams) -> void:
	if a_scenario == null:
		return
	var built: Map = _dock.build_for(a_scenario, a_result.map)
	if built == null:
		return
	MapImageReimport.tag(built)
	var old_map: Map = _dock.map_of(a_scenario)
	var kept: Array[Dictionary] = []
	if old_map != null:
		kept = MapImageReimport.hand_placed_children(old_map, a_scenario)
	var held: Map = _dock.detach_map(a_scenario)
	_dock.install(a_scenario, built)
	var extra := PackedStringArray()
	var moved: Array[Node] = MapImageReimport.move_onto(kept, built, a_scenario)
	if not moved.is_empty():
		extra.append(
			(
				"Kept from the old map: %s"
				% ", ".join(moved.map(func(node: Node) -> String: return String(node.name)))
			)
		)
	if held != null:
		held.queue_free()
	var flags: Dictionary = MapImageReimport.flag(
		built.terrain_data,
		a_result.water.depth_by_cell,
		a_result.structures.footprints(),
		MapImageReimport.hand_placed_pieces(a_scenario, built)
	)
	for line: String in flags.lines:
		extra.append("FLAGGED: %s" % line)
	var flagged: Array[Vector2i] = flags.cells
	_show(a_result, a_params, flagged, extra)
	_save_button.disabled = false
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().scan()


func _show(
	a_result: MapImageImporter,
	a_params: MapImageImportParams,
	a_flagged: Array[Vector2i],
	a_extra: PackedStringArray
) -> void:
	var lines: PackedStringArray = MapImageImportReport.lines(a_result, _path.text.get_file())
	if a_result.cells != null and not a_extra.is_empty():
		lines.append("")
		lines.append_array(a_extra)
	_report.text = "\n".join(lines)
	var image: Image = (
		MapImageImportReport.readout(a_result, a_params, a_flagged)
		if a_result.cells != null
		else null
	)
	_readout.show_image(
		image, func(cell: Vector2i) -> String: return _describe_import(a_result, cell)
	)


## What the import readout shows at `a_cell`: the drawing pixel, what each layer says there, and
## the issue that marks it.
static func _describe_import(a_result: MapImageImporter, a_cell: Vector2i) -> String:
	var cells: MapImageCells = a_result.cells
	if cells == null:
		return ""
	var parts := PackedStringArray()
	var pixel: Vector2i = a_cell
	if cells.side == 0:
		# Refused before the grid was fitted: the readout is the drawing, read pixel by pixel.
		parts = _layers_at(a_result.layers, pixel)
	elif cells.has_cell(a_cell):
		pixel = cells.pixel_of(a_cell)
		var index: int = cells.index_of(a_cell)
		for meaning: int in [
			cells.terrain[index], cells.water[index], cells.cliffs[index], cells.structures[index]
		]:
			if meaning != MapImagePalette.Meaning.NONE:
				parts.append(MapImagePalette.LABELS[meaning])
	else:
		return ""
	var issues: Array[Dictionary] = MapImageIssues.of(a_result)
	for i: int in issues.size():
		if (issues[i].pixels as Array).has(pixel):
			parts.append(MapImageIssues.line(i, issues[i].message))
	return "px (%d, %d): %s" % [pixel.x, pixel.y, "; ".join(parts)]


## What each layer of `a_layers` says at drawing pixel `a_pixel`, a colour outside its layer's
## palette by its hex code.
static func _layers_at(a_layers: MapImageLayers, a_pixel: Vector2i) -> PackedStringArray:
	var out := PackedStringArray()
	if a_layers == null or not Rect2i(Vector2i.ZERO, a_layers.size).has_point(a_pixel):
		return out
	for layer: int in a_layers.images:
		var color: Color = (a_layers.images[layer] as Image).get_pixelv(a_pixel)
		var meaning: int = MapImagePalette.meaning_of(layer, color.r8, color.g8, color.b8, color.a8)
		if meaning > 0:
			out.append(MapImagePalette.LABELS[meaning])
		elif meaning < 0:
			out.append(
				(
					"%s: %s is not in the palette"
					% [MapImagePalette.LAYER_NAMES[layer], MapImagePalette.hex(color)]
				)
			)
	return out


## What the export readout shows at `a_cell`: where a unit can walk there on the map and on the
## drawing's re-import.
static func _describe_export(a_exported: MapImageExporter, a_cell: Vector2i) -> String:
	return "px (%d, %d): %s" % [a_cell.x, a_cell.y, a_exported.passability_at(a_cell)]


## Read the open Scenario's map into a drawing and ask where to write it. An export that fails
## its own import check writes nothing, and the report says why.
func export_map() -> void:
	if prepare_export():
		_ask_export_path()


## Read the open Scenario's map into the pending export. False, with the report saying why, when
## there is no map or the drawing fails its own import check.
func prepare_export() -> bool:
	_pending_export = null
	var scenario: Node = _dock.scenario_source.call()
	var map: Map = _dock.map_of(scenario) if scenario != null else null
	if map == null:
		_report.text = NO_MAP_MESSAGE
		return false
	var exported: MapImageExporter = MapImageExporter.from_map(map, params())
	if not exported.is_valid():
		_report.text = "\n".join(PackedStringArray(["Export FAILED:"]) + exported.errors)
		return false
	_pending_export = exported
	_pending_name = DEFAULT_DRAWING_NAME % String(scenario.name).to_snake_case()
	return true


## Made on first use, like the browse dialog: an EditorFileDialog exists only in the editor.
func _ask_export_path() -> void:
	if _export_dialog == null:
		_export_dialog = EditorFileDialog.new()
		# A save dialog asks before replacing a file that already exists.
		_export_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
		_export_dialog.access = EditorFileDialog.ACCESS_RESOURCES
		_export_dialog.title = EXPORT_TITLE
		_export_dialog.add_filter(EXPORT_FILTER)
		_export_dialog.file_selected.connect(export_to)
		add_child(_export_dialog)
	_export_dialog.current_file = _pending_name
	_export_dialog.popup_file_dialog()


## Write the pending export to `a_path`, and report it with what the palette could not carry.
func export_to(a_path: String) -> void:
	if _pending_export == null:
		return
	var error: Error = _pending_export.write(a_path)
	var lines := PackedStringArray()
	if error != OK:
		lines.append("Export FAILED: cannot write %s (%s)" % [a_path, error_string(error)])
	else:
		lines.append("Exported %s" % a_path)
		lines.append(EXPORT_WARNING)
		lines.append(PASSAGE_KEY)
		if not _pending_export.notes.is_empty():
			lines.append("")
			lines.append_array(_pending_export.notes)
	_report.text = "\n".join(lines)
	var image: Image = _pending_export.readout() if error == OK else null
	var exported: MapImageExporter = _pending_export
	_readout.show_image(
		image, func(cell: Vector2i) -> String: return _describe_export(exported, cell)
	)
	_pending_export = null
	if error == OK and Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().scan()


func report_text() -> String:
	return _report.text


func _ask_save() -> void:
	_dock.ask_save_path(DEFAULT_MAP_NAME % _path.text.get_file().get_basename().get_basename())


## Made on first use, like the dock's save dialog: an EditorFileDialog exists only in the editor.
func _browse() -> void:
	if _file_dialog == null:
		_file_dialog = EditorFileDialog.new()
		_file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
		_file_dialog.access = EditorFileDialog.ACCESS_RESOURCES
		_file_dialog.filters = FILE_FILTERS
		_file_dialog.file_selected.connect(set_drawing_path)
		add_child(_file_dialog)
	_file_dialog.popup_file_dialog()
#endregion
