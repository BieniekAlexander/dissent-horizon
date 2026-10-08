class_name DebugFogRow
extends HBoxContainer

## The debug menu's fog setting: lift the fog, or show it as the viewer sees it — the local
## player, or the bot a spectator is viewing (DebugMode.set_fog_lifted). Shown only while the
## debug view is up; with it down the fog is always shown.

enum Choice { LIFTED, SHOWN }

const CHOICE_LABELS: Dictionary = {
	Choice.LIFTED: "Off",
	Choice.SHOWN: "As the viewer sees it",
}
## Matches the label column of the debug menu's other rows.
const LABEL_WIDTH: float = 70.0

var _picker: OptionButton


func _ready() -> void:
	# Readable while a scripted beat has paused the world, like the rest of the debug HUD.
	process_mode = Node.PROCESS_MODE_ALWAYS
	var label := Label.new()
	label.text = "Fog"
	label.custom_minimum_size = Vector2(LABEL_WIDTH, 0.0)
	add_child(label)
	_picker = OptionButton.new()
	_picker.name = "Picker"
	_picker.focus_mode = Control.FOCUS_NONE
	_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for choice: int in CHOICE_LABELS:
		_picker.add_item(CHOICE_LABELS[choice], choice)
	_picker.item_selected.connect(
		func(a_index: int) -> void:
			DebugMode.set_fog_lifted(_picker.get_item_id(a_index) == Choice.LIFTED)
	)
	add_child(_picker)
	_sync()


# Polled rather than signalled: DebugMode is a static switch with no signal, and a session
# starting resets it from outside.
func _process(_a_delta: float) -> void:
	_sync()


## Pick `a_choice`, as a click on it would.
func choose(a_choice: Choice) -> void:
	_picker.select(_picker.get_item_index(a_choice))
	_picker.item_selected.emit(_picker.selected)


func _sync() -> void:
	visible = DebugMode.is_active()
	var choice: Choice = Choice.LIFTED if DebugMode.is_fog_lifted() else Choice.SHOWN
	var index: int = _picker.get_item_index(choice)
	if _picker.selected != index:
		_picker.select(index)
