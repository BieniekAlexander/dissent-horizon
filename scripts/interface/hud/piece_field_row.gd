class_name PieceFieldRow
extends HBoxContainer

## One PieceField as a line of a readout popup: its label and its value. The one template every
## readout row is, read-only for a player and an editor in debug tuning — the same row, with the
## value made editable (gdd/systems/ux/ui/piece-readouts.md, debug-tuning.md).
##
## An editor shows the doc's value, and dims one the doc leaves to its default. Committing writes
## the doc through the TuningSession, which previews it on the pieces.

const LABEL_WIDTH: float = 140.0
const EDITOR_WIDTH: float = 150.0
const FONT_SIZE: int = 12
const LABEL_COLOR: Color = Color(0.62, 0.65, 0.61)
const VALUE_COLOR: Color = Color(0.88, 0.89, 0.88)
## A value the doc does not state: the default, shown as what the running piece holds.
const DEFAULT_COLOR: Color = Color(0.55, 0.57, 0.55)
const ERROR_COLOR: Color = Color(1.0, 0.45, 0.4)
const NONE_ITEM: String = "none"
## What an `is_live = false` field says beside its editor.
const AFTER_IMPORT_NOTE: String = "applies after a re-import"
## A cadence editor's three states.
const CADENCE_ITEMS: Array[String] = ["none", "once", "every…"]
## The doc name a flag checkbox stands for; its text is the readable form.
const FLAG_META: StringName = &"flag"

## Raised after a committed edit, so the popup can re-read rows that depend on it.
signal committed

var field: PieceField
var ctx: Dictionary
## Debug tuning only: where the value lives, who to write it through, and for which piece type
## and scope index. A row with no session is read-only.
var session: TuningSession = null
var address: Dictionary = {}
var piece_id: StringName = &""
var index: int = 0

var _error: Label = null


## A read-only row: the running piece's value.
static func reading(a_field: PieceField, a_ctx: Dictionary) -> PieceFieldRow:
	var row := PieceFieldRow.new()
	row.field = a_field
	row.ctx = a_ctx
	row._build()
	return row


## An editing row, writing through `a_session` to the doc at `a_address`.
static func editing(
	a_field: PieceField,
	a_ctx: Dictionary,
	a_session: TuningSession,
	a_address: Dictionary,
	a_piece: StringName,
	a_index: int
) -> PieceFieldRow:
	var row := PieceFieldRow.new()
	row.field = a_field
	row.ctx = a_ctx
	row.session = a_session
	row.address = a_address
	row.piece_id = a_piece
	row.index = a_index
	row._build()
	return row


func _build() -> void:
	add_theme_constant_override("separation", 6)
	var label: Label = _label(field.label, LABEL_COLOR)
	label.custom_minimum_size.x = LABEL_WIDTH
	add_child(label)
	if session == null:
		add_child(_label(PieceFields.display(field, field.read_raw(ctx)), VALUE_COLOR))
		return
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	var shown: Dictionary = session.shown_value(address, field, ctx)
	var editor: Control = _editor(shown["value"], shown["is_default"])
	editor.custom_minimum_size.x = EDITOR_WIDTH
	column.add_child(editor)
	if not field.is_live:
		column.add_child(_label(AFTER_IMPORT_NOTE, DEFAULT_COLOR))
	_error = _label("", ERROR_COLOR)
	_error.visible = false
	_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_error)
	add_child(column)
	_wire_outline(editor)


#region Editors
func _editor(a_value: Variant, a_is_default: bool) -> Control:
	match field.kind:
		PieceField.Kind.BOOL:
			var box := CheckBox.new()
			box.button_pressed = a_value == true
			box.toggled.connect(func(on: bool) -> void: _commit(on))
			return box
		PieceField.Kind.ENUM:
			return _options(_enum_items(), a_value, false)
		PieceField.Kind.SPEED_CLASS:
			return _options(_speed_items(), a_value, false)
		PieceField.Kind.SHAPE:
			return _options(_shape_items(), a_value, field.is_optional)
		PieceField.Kind.FLAGS, PieceField.Kind.ID_LIST:
			return _flags(a_value)
		PieceField.Kind.SHAPE_PAIR:
			return _shape_pair(a_value)
		PieceField.Kind.CADENCE:
			return _cadence(a_value)
	return _text(a_value, a_is_default)


## A typed value. Left empty, it returns the field to its default (the key is removed).
func _text(a_value: Variant, a_is_default: bool) -> LineEdit:
	var edit := LineEdit.new()
	var text: String = "" if a_value == null else _plain(a_value)
	if a_is_default:
		edit.placeholder_text = text
	else:
		edit.text = text
	edit.add_theme_font_size_override("font_size", FONT_SIZE)
	edit.gui_input.connect(_refuse_verbose_key.bind(edit))
	var commit := func() -> void:
		var parsed: Variant = _parse(edit.text)
		if parsed is String and field.kind != PieceField.Kind.TEXT and not edit.text.is_empty():
			_show_error(parsed)
			return
		_commit(parsed)
	edit.text_submitted.connect(func(_t: String) -> void: commit.call())
	edit.focus_exited.connect(commit)
	return edit


func _options(a_items: Array, a_value: Variant, a_optional: bool) -> OptionButton:
	var options := OptionButton.new()
	options.add_theme_font_size_override("font_size", FONT_SIZE)
	var values: Array = []
	if a_optional:
		options.add_item(NONE_ITEM)
		values.append(null)
	for item: Array in a_items:
		options.add_item(item[1])
		values.append(item[0])
	var at: int = values.find(a_value)
	if at < 0 and a_value != null:
		options.add_item(str(a_value))
		values.append(a_value)
		at = values.size() - 1
	options.select(maxi(at, 0))
	options.item_selected.connect(func(i: int) -> void: _commit(values[i]))
	return options


## One checkbox per name a FLAGS or ID_LIST field may hold, wrapping onto further lines.
func _flags(a_value: Variant) -> HFlowContainer:
	var box := HFlowContainer.new()
	var chosen: Array = a_value if a_value is Array else []
	for name: String in field.options:
		var check := CheckBox.new()
		check.text = name.to_lower().replace("_", " ")
		check.add_theme_font_size_override("font_size", FONT_SIZE)
		check.button_pressed = chosen.has(name)
		check.set_meta(FLAG_META, name)
		check.toggled.connect(func(_on: bool) -> void: _commit(_checked(box)))
		box.add_child(check)
	return box


func _shape_pair(a_value: Variant) -> HBoxContainer:
	var box := HBoxContainer.new()
	var pair: Dictionary = a_value if a_value is Dictionary else {}
	var ids: Array = session.shape_ids(str(field.options[0]))
	var pickers: Array[OptionButton] = []
	for end: String in ["from", "to"]:
		var picker := OptionButton.new()
		picker.add_theme_font_size_override("font_size", FONT_SIZE)
		for id: String in ids:
			picker.add_item("%s %s" % [end, id.trim_prefix(str(field.options[0]))])
		picker.select(maxi(ids.find(str(pair.get(end, ""))), 0))
		pickers.append(picker)
		box.add_child(picker)
	for picker: OptionButton in pickers:
		picker.item_selected.connect(
			func(_i: int) -> void:
				_commit({"from": ids[pickers[0].selected], "to": ids[pickers[1].selected]})
		)
	return box


func _cadence(a_value: Variant) -> HBoxContainer:
	var box := HBoxContainer.new()
	var mode := OptionButton.new()
	mode.add_theme_font_size_override("font_size", FONT_SIZE)
	for item: String in CADENCE_ITEMS:
		mode.add_item(item)
	var seconds := LineEdit.new()
	seconds.custom_minimum_size.x = 56.0
	seconds.gui_input.connect(_refuse_verbose_key.bind(seconds))
	var is_every: bool = a_value != null and str(a_value) != "once"
	mode.select(0 if a_value == null else (2 if is_every else 1))
	seconds.text = _plain(a_value) if is_every else ""
	seconds.visible = is_every
	var commit := func() -> void:
		match mode.selected:
			0:
				_commit(null)
			1:
				_commit("once")
			2:
				if seconds.text.is_valid_float():
					_commit(float(seconds.text))
	mode.item_selected.connect(
		func(i: int) -> void:
			seconds.visible = i == 2
			commit.call()
	)
	seconds.text_submitted.connect(func(_t: String) -> void: commit.call())
	box.add_child(mode)
	box.add_child(seconds)
	return box


func _enum_items() -> Array:
	var items: Array = []
	for name: String in field.options:
		items.append([name, name.to_lower().replace("_", " ")])
	return items


func _speed_items() -> Array:
	var items: Array = []
	var ladder: Dictionary = session.speed_ladder()
	for name: String in ladder:
		items.append([name, "%s  (%s u/s)" % [name, ladder[name]]])
	return items


func _shape_items() -> Array:
	var items: Array = []
	for id: String in session.shape_ids(str(field.options[0])):
		items.append([id, "%s  (%s)" % [id, session.shape_radius(id)]])
	return items


## The doc names of the flags ticked in a FLAGS editor.
static func _checked(a_box: Container) -> Array:
	var names: Array = []
	for check: Node in a_box.get_children():
		if (check as CheckBox).button_pressed:
			names.append(check.get_meta(FLAG_META))
	return names


#endregion


#region Committing
func _commit(a_value: Variant) -> void:
	var error: String = session.edit(address, field, a_value, piece_id, index)
	_show_error(error)
	if error.is_empty():
		committed.emit()


## A typed value as the field wants it, or an error String. Empty text is null: the default.
func _parse(a_text: String) -> Variant:
	var text: String = a_text.strip_edges()
	if text.is_empty():
		return null
	match field.kind:
		PieceField.Kind.INTEGER:
			return int(text) if text.is_valid_int() else "a whole number"
		PieceField.Kind.NUMBER, PieceField.Kind.SPEED_CLASS:
			return float(text) if text.is_valid_float() else "a number"
	return text


func _show_error(a_error: Variant) -> void:
	if _error == null:
		return
	_error.text = str(a_error) if a_error is String else ""
	_error.visible = not _error.text.is_empty()


## `ui_verbose` deepens the readout while it is held, so it is never typed into a field.
static func _refuse_verbose_key(a_event: InputEvent, a_field: Control) -> void:
	if a_event is InputEventKey and a_event.is_action("ui_verbose"):
		a_field.accept_event()


#endregion


#region Outline
## While the editor is hovered or focused, draw the volume this field sizes on the piece.
func _wire_outline(a_editor: Control) -> void:
	if not field.shape_node.is_valid():
		return
	var show := func() -> void: ShapeOutline.show_on(field.shape_node.call(ctx))
	var hide := func() -> void:
		if not a_editor.has_focus():
			ShapeOutline.hide_on(field.shape_node.call(ctx))
	a_editor.mouse_entered.connect(show)
	a_editor.focus_entered.connect(show)
	a_editor.mouse_exited.connect(hide)
	a_editor.focus_exited.connect(func() -> void: ShapeOutline.hide_on(field.shape_node.call(ctx)))
	tree_exiting.connect(func() -> void: ShapeOutline.hide_on(field.shape_node.call(ctx)))


#endregion


static func _plain(a_value: Variant) -> String:
	if a_value is float and is_equal_approx(a_value, roundf(a_value)):
		return str(int(a_value))
	return str(a_value)


static func _label(a_text: String, a_color: Color) -> Label:
	var label := Label.new()
	label.text = a_text
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_color", a_color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
