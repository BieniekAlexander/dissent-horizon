class_name ReplaySaveForm
extends VBoxContainer

## "Save replay" at the end of a match: a button that opens a name field, prefilled with
## `<scenario>_<timestamp>`, and writes the match's recording under that name as a KEPT replay —
## one the autosave rotation never deletes. gdd/systems/commands/recording-and-replay.md §Watching.
##
## The name rules are ReplayNames.kept_name_refusal's. A character no file name can hold is
## refused AS TYPED (taken back out of the field, with the reason shown); a name that would
## join the autosave rotation is refused on saving; and a name already taken asks before
## overwriting — the Save button becomes Overwrite until the name changes.

## The recording was written, to `path`.
signal saved(path: String)

## Where kept replays are written. A test points it elsewhere.
var directory: String = ReplayFile.DIRECTORY

var _recorder: ReplayRecorder = null
var _open_button: Button
var _row: HBoxContainer
var _name_field: LineEdit
var _save_button: Button
var _status: Label
## The name the player has agreed to overwrite; any edit takes the agreement back.
var _confirmed_overwrite: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_open_button = Button.new()
	_open_button.name = "SaveReplayButton"
	_open_button.text = "Save replay"
	_open_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_open_button.pressed.connect(open)
	add_child(_open_button)
	_row = HBoxContainer.new()
	_row.visible = false
	add_child(_row)
	_name_field = LineEdit.new()
	_name_field.name = "NameField"
	_name_field.custom_minimum_size = Vector2(260.0, 0.0)
	_name_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_field.text_changed.connect(_on_name_changed)
	_name_field.text_submitted.connect(func(_a_text: String) -> void: save())
	_row.add_child(_name_field)
	_save_button = Button.new()
	_save_button.name = "SaveButton"
	_save_button.text = "Save"
	_save_button.pressed.connect(save)
	_row.add_child(_save_button)
	_status = Label.new()
	_status.name = "Status"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(260.0, 0.0)
	add_child(_status)


## Save `a_recorder`'s recording. The form is not offered without one.
func bind(a_recorder: ReplayRecorder) -> void:
	_recorder = a_recorder
	visible = _recorder != null


## Open the name field, prefilled with the default name.
func open() -> void:
	var scenario_name: String = _recorder.replay.scenario_name() if _recorder != null else ""
	_name_field.text = ReplayNames.default_kept_name(
		scenario_name if not scenario_name.is_empty() else "replay",
		int(Time.get_unix_time_from_system())
	)
	_confirmed_overwrite = ""
	_open_button.visible = false
	_row.visible = true
	_status.text = ""
	_save_button.text = "Save"
	_name_field.grab_focus()


func is_open() -> bool:
	return _row.visible


## The name in the field.
func entered_name() -> String:
	return _name_field.text


## Type `a_text` into the name field, as the player would.
func type_name(a_text: String) -> void:
	_name_field.text = a_text
	_on_name_changed(a_text)


func status_text() -> String:
	return _status.text


## Whether the next Save overwrites a replay already kept under the name.
func is_asking_to_overwrite() -> bool:
	return _save_button.text == "Overwrite"


## Save under the name in the field, or say why not: a refused name, or — the first time — a
## name already taken.
func save() -> void:
	if _recorder == null:
		return
	var name: String = _name_field.text.strip_edges()
	var refused: String = ReplayNames.kept_name_refusal(name)
	if not refused.is_empty():
		_status.text = refused
		return
	var path: String = directory.path_join("%s.%s" % [name, ReplayFile.EXTENSION])
	if FileAccess.file_exists(path) and _confirmed_overwrite != name:
		_confirmed_overwrite = name
		_save_button.text = "Overwrite"
		_status.text = "A replay named '%s' exists. Overwrite it?" % name
		return
	DirAccess.make_dir_recursive_absolute(directory)
	var result: Error = _recorder.write_kept(path)
	if result != OK:
		_status.text = "Could not save the replay: %s" % error_string(result)
		return
	_row.visible = false
	_status.text = "Saved as '%s'." % name
	saved.emit(path)


## Take back out any character a file name cannot hold, and say why; any edit also takes back an
## agreement to overwrite.
func _on_name_changed(a_text: String) -> void:
	var kept: String = a_text
	var refused: String = ""
	for character: String in ReplayNames.FORBIDDEN_CHARACTERS:
		if kept.contains(character):
			kept = kept.replace(character, "")
			refused = character
	if kept != a_text:
		var caret: int = _name_field.caret_column
		_name_field.text = kept
		_name_field.caret_column = mini(caret, kept.length())
		_status.text = "A file name cannot hold '%s'." % refused
	else:
		_status.text = ""
	_confirmed_overwrite = ""
	_save_button.text = "Save"
