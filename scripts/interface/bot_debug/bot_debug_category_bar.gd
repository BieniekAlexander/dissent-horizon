class_name BotDebugCategoryBar
extends HBoxContainer

## The spectator HUD's picker for which category of a bot's signals the debug overlay draws
## (BotDebugOverlay.active_category). Shown only while the debug view is up, which is the only
## time the overlay draws anything.

var _picker: OptionButton


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	var label := Label.new()
	label.text = "Bot overlay"
	add_child(label)
	_picker = OptionButton.new()
	_picker.name = "Picker"
	for category: int in BotDebugOverlay.CATEGORY_LABELS:
		_picker.add_item(BotDebugOverlay.CATEGORY_LABELS[category], category)
	_picker.item_selected.connect(_on_item_selected)
	add_child(_picker)
	_sync()


# Polled rather than signalled: DebugMode is a static switch with no signal, and the overlay's
# category can be reset from outside (a session ending).
func _process(_a_delta: float) -> void:
	_sync()


## Pick `a_category`, as a click on it would.
func choose(a_category: BotDebugOverlay.Category) -> void:
	_picker.select(_picker.get_item_index(a_category))
	_on_item_selected(_picker.selected)


func _on_item_selected(a_index: int) -> void:
	BotDebugOverlay.active_category = _picker.get_item_id(a_index) as BotDebugOverlay.Category


func _sync() -> void:
	visible = DebugMode.is_active()
	var index: int = _picker.get_item_index(BotDebugOverlay.active_category)
	if _picker.selected != index:
		_picker.select(index)
