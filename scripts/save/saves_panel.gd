class_name SavesPanel
extends VBoxContainer

## The saved games, as the pause menu and the title screen show them: a row per save, newest
## first, that loads it when pressed — and, in a running match (`can_save`), a name field that
## saves the match under that name. Built in code. gdd/systems/commands/saved-games.md §Menus.
##
## Saving over an existing save asks first: the button turns to "Overwrite" and the second press
## writes. The autosave cannot be saved over by name; a player keeps one by renaming its file.

## A save was written, at `path`.
signal saved(path: String)

## Whether this panel offers saving: set before it enters the tree.
var can_save: bool = false
## The match a save is taken of. Set with `can_save`.
var scenario: Scenario = null
## Where the saves are. A test points it elsewhere.
var directory: String = SaveGame.DIRECTORY

var _name_field: LineEdit = null
var _save_button: Button = null
var _list: VBoxContainer = null
var _status: Label = null
## The name the save button last asked to overwrite; a second press on it writes.
var _confirming: String = ""


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	if can_save:
		var row := HBoxContainer.new()
		row.name = "SaveRow"
		_name_field = LineEdit.new()
		_name_field.name = "SaveName"
		_name_field.placeholder_text = "Save name"
		_name_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_name_field.text_changed.connect(func(_t: String) -> void: _set_confirming(""))
		_name_field.text_submitted.connect(func(_t: String) -> void: save_named(_name_field.text))
		row.add_child(_name_field)
		_save_button = Button.new()
		_save_button.name = "SaveButton"
		_save_button.text = "Save"
		_save_button.pressed.connect(func() -> void: save_named(_name_field.text))
		row.add_child(_save_button)
		add_child(row)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(320, 180)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list = VBoxContainer.new()
	_list.name = "SaveList"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	add_child(scroll)
	_status = Label.new()
	_status.name = "Status"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(320, 0)
	_status.add_theme_color_override("font_color", Color(0.9, 0.55, 0.45, 1))
	add_child(_status)
	refresh()


## Re-read the saves on disk, and whether the match can be saved now.
func refresh() -> void:
	if _list == null:
		return
	for child: Node in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	var entries: Array[Dictionary] = SaveGame.entries(directory)
	if entries.is_empty():
		var none := Label.new()
		none.text = "No saved games."
		_list.add_child(none)
	for entry: Dictionary in entries:
		var button := Button.new()
		button.text = SaveGame.label_for(entry)
		button.pressed.connect(load_save.bind(entry["path"]))
		_list.add_child(button)
	if _save_button != null:
		var refused: String = SaveGame.refusal_to_save(scenario)
		_save_button.disabled = not refused.is_empty()
		_save_button.tooltip_text = refused


## The rows, top to bottom.
func labels() -> Array[String]:
	var out: Array[String] = []
	for child: Node in _list.get_children():
		if child is Button:
			out.append((child as Button).text)
	return out


func status() -> String:
	return _status.text


## Save the match as `a_name`. Asks first when a save of that name exists.
func save_named(a_name: String) -> void:
	var name: String = SaveGame.valid_name(a_name)
	if name.is_empty():
		_status.text = "A save's name is letters, digits, spaces, - and _, and not 'autosave'."
		return
	var refused: String = SaveGame.refusal_to_save(scenario)
	if not refused.is_empty():
		_status.text = "Cannot save: %s." % refused
		return
	var path: String = SaveGame.path_for(name, directory)
	if FileAccess.file_exists(path) and _confirming != name:
		_set_confirming(name)
		_status.text = "'%s' exists. Press Overwrite to replace it." % name
		return
	_set_confirming("")
	var result: Error = SaveGame.write(scenario, path)
	if result != OK:
		_status.text = "Could not save: %s." % error_string(result)
		return
	_status.text = "Saved '%s'." % name
	refresh()
	saved.emit(path)


## Load the save at `a_path`; show why when it cannot be.
func load_save(a_path: String) -> void:
	_status.text = SceneManager.load_save(a_path)


func _set_confirming(a_name: String) -> void:
	_confirming = a_name
	if _save_button != null:
		_save_button.text = "Save" if a_name.is_empty() else "Overwrite"
