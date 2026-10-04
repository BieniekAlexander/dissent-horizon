class_name DebugTuningPanel
extends PanelContainer

## The debug tuning menu, top-left: the libraries many pieces name (the speed ladder, the shape
## buckets) and the save that writes every edited doc back. Up exactly while the debug view is,
## standing in for the resource bars named in `hidden_while_up` — a debug session has broken the
## match's economy already. gdd/systems/ux/ui/debug-tuning.md.
##
## The LAYOUT of its frame is authored in scenes/interface/debug_tuning_panel.tscn; the rows are
## built here from the session's docs.

const WIDTH: float = 330.0
## The share of the viewport's height the menu may take before it scrolls.
const MAX_HEIGHT_FRACTION: float = 0.5
const FONT_SIZE: int = 12
const HEADER_COLOR: Color = Color(0.95, 0.85, 0.55)
const NOTE_COLOR: Color = Color(0.6, 0.63, 0.59)
const ERROR_COLOR: Color = Color(1.0, 0.45, 0.4)
const SAVED_COLOR: Color = Color(0.55, 0.9, 0.6)
const FOLD_TEXT: String = "–"
const UNFOLD_TEXT: String = "+"
## The shape library's buckets, by id prefix, in the order and under the names they are listed.
const SHAPE_GROUPS: Array = [
	["ground_range_", "Ground reach"],
	["air_range_", "Air reach"],
	["vision_", "Vision"],
	["detection_", "Detection"],
	["aoe_", "Blast"],
]
const IMPORT_NOTE: String = "Saved values reach the scenes when the importer is next run."

## The HUD nodes this menu stands in for while it is up (the resource bars). Paths are relative
## to this node.
@export var hidden_while_up: Array[NodePath] = []

var _session: TuningSession = null
var _is_up: bool = false
var _restored_visibility: Dictionary = {}
var _body: VBoxContainer
var _libraries: VBoxContainer
var _results: VBoxContainer
var _save: Button
var _fold: Button


func _ready() -> void:
	visible = false
	if Engine.is_editor_hint():
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	custom_minimum_size.x = WIDTH
	var column := VBoxContainer.new()
	add_child(column)
	var title_row := HBoxContainer.new()
	var title := _label("Tuning", HEADER_COLOR)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	_fold = Button.new()
	_fold.text = FOLD_TEXT
	_fold.focus_mode = Control.FOCUS_NONE
	_fold.pressed.connect(
		func() -> void:
			_body.visible = not _body.visible
			_fold.text = FOLD_TEXT if _body.visible else UNFOLD_TEXT
	)
	title_row.add_child(_fold)
	column.add_child(title_row)
	_body = VBoxContainer.new()
	column.add_child(_body)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y = get_viewport_rect().size.y * MAX_HEIGHT_FRACTION
	_body.add_child(scroll)
	_libraries = VBoxContainer.new()
	_libraries.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_libraries)
	_save = Button.new()
	_save.focus_mode = Control.FOCUS_NONE
	_save.pressed.connect(_on_save)
	_body.add_child(_save)
	_results = VBoxContainer.new()
	_body.add_child(_results)
	_body.add_child(_label(IMPORT_NOTE, NOTE_COLOR, true))


func _process(_a_delta: float) -> void:
	var is_up: bool = DebugMode.is_active()
	if is_up != _is_up:
		_is_up = is_up
		visible = is_up
		_replace_hud(is_up)
		if is_up and _session == null:
			_session = TuningSession.of(self)
			_build_libraries()
	if is_up and _session != null:
		var unsaved: int = _session.unsaved_paths().size()
		_save.text = "Save %d edited doc%s" % [unsaved, "" if unsaved == 1 else "s"]
		_save.disabled = unsaved == 0


func _replace_hud(a_is_up: bool) -> void:
	for path: NodePath in hidden_while_up:
		var node: CanvasItem = get_node_or_null(path) as CanvasItem
		if node == null:
			continue
		if a_is_up:
			_restored_visibility[path] = node.visible
			node.visible = false
		else:
			node.visible = _restored_visibility.get(path, true)


#region Libraries
func _build_libraries() -> void:
	for child: Node in _libraries.get_children():
		child.queue_free()
	_libraries.add_child(_label("Speed classes (u/s)", HEADER_COLOR))
	var ladder: Dictionary = _session.speed_ladder()
	for name: String in ladder:
		_libraries.add_child(
			_value_row(
				name, ladder[name], func(v: float) -> String: return _session.set_speed(name, v)
			)
		)
	for group: Array in SHAPE_GROUPS:
		var ids: Array = _session.shape_ids(group[0])
		if ids.is_empty():
			continue
		_libraries.add_child(_label("%s (radius)" % group[1], HEADER_COLOR))
		for id: String in ids:
			_libraries.add_child(
				_value_row(
					id.trim_prefix(group[0]),
					_session.shape_radius(id),
					func(v: float) -> String: return _session.set_shape_radius(id, v)
				)
			)


## One library entry: its name and a number field. A refused value is put back and the reason
## shown under it.
func _value_row(a_name: String, a_value: Variant, a_set: Callable) -> Control:
	var column := VBoxContainer.new()
	var row := HBoxContainer.new()
	var label := _label(a_name, NOTE_COLOR)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var edit := LineEdit.new()
	edit.custom_minimum_size.x = 80.0
	edit.text = str(a_value)
	edit.add_theme_font_size_override("font_size", FONT_SIZE)
	edit.gui_input.connect(PieceFieldRow._refuse_verbose_key.bind(edit))
	row.add_child(edit)
	column.add_child(row)
	var error := _label("", ERROR_COLOR, true)
	error.visible = false
	column.add_child(error)
	# The value the field last held: a refused edit is put back to it. In an array because a
	# lambda cannot reassign a captured local.
	var held: Array = [str(a_value)]
	var commit := func() -> void:
		if edit.text == held[0]:
			return
		var message: String = (
			a_set.call(float(edit.text)) if edit.text.is_valid_float() else "a number"
		)
		error.text = message
		error.visible = not message.is_empty()
		if message.is_empty():
			held[0] = edit.text
		else:
			edit.text = held[0]
	edit.text_submitted.connect(func(_t: String) -> void: commit.call())
	edit.focus_exited.connect(commit)
	return column


#endregion


#region Saving
func _on_save() -> void:
	for child: Node in _results.get_children():
		child.queue_free()
	var report: Dictionary = _session.save()
	if not (report["saved"] as Array).is_empty():
		_results.add_child(
			_label("Saved %d doc(s)." % (report["saved"] as Array).size(), SAVED_COLOR)
		)
	for refusal: Dictionary in report["refused"]:
		_results.add_child(_refusal(refusal))


## A refused doc: the importer's reason, and — for a calibration rule — a place to say why the
## piece breaks it on purpose, saved as its waiver.
func _refusal(a_refusal: Dictionary) -> Control:
	var column := VBoxContainer.new()
	var who: String = a_refusal["id"] if not str(a_refusal["id"]).is_empty() else "not saved"
	column.add_child(_label("%s: %s" % [who, a_refusal["message"]], ERROR_COLOR, true))
	if str(a_refusal["rule"]).is_empty():
		return column
	var row := HBoxContainer.new()
	var reason := LineEdit.new()
	reason.placeholder_text = "why %s is built this way" % a_refusal["id"]
	reason.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reason.gui_input.connect(PieceFieldRow._refuse_verbose_key.bind(reason))
	row.add_child(reason)
	var waive := Button.new()
	waive.text = "Waive %s" % a_refusal["rule"]
	waive.focus_mode = Control.FOCUS_NONE
	waive.pressed.connect(
		func() -> void:
			if reason.text.strip_edges().is_empty():
				return
			var error: String = _session.waive(
				a_refusal["path"], a_refusal["rule"], reason.text.strip_edges()
			)
			if error.is_empty():
				_on_save()
			else:
				column.add_child(_label(error, ERROR_COLOR, true))
	)
	row.add_child(waive)
	column.add_child(row)
	return column


#endregion


func _label(a_text: String, a_color: Color, a_wraps: bool = false) -> Label:
	var label := Label.new()
	label.text = a_text
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_color", a_color)
	if a_wraps:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = WIDTH - 16.0
	return label
