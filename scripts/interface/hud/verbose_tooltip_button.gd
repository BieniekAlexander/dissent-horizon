class_name VerboseTooltipButton
extends Button

## A Button with two tooltip variants shown through a CUSTOM popup rather than
## Godot's built-in tooltip. The built-in tooltip captures its text when it opens
## on hover and can't be refreshed mid-hover; this custom popup can, so pressing
## or releasing the "ui_verbose" action (Alt) while the tooltip is open swaps it
## live between `simple_tooltip` and `verbose_tooltip`. Buttons with no verbose
## text just keep showing the simple one.

var simple_tooltip: String = ""
var verbose_tooltip: String = ""

## Shared, lazily-created overlay reused by every VerboseTooltipButton — only one
## tooltip is ever visible at a time. Lives above the HUD on its own CanvasLayer,
## parented to the window root so it survives scene changes.
static var _layer: CanvasLayer = null
static var _panel: PanelContainer = null
static var _label: Label = null
## The button whose tooltip is currently shown, so only it live-refreshes.
static var _active: VerboseTooltipButton = null

const _DEFAULT_DELAY: float = 0.5
const _CURSOR_OFFSET: Vector2 = Vector2(16, 16)

var _hover_timer: Timer

func _ready() -> void:
	# Suppress the built-in tooltip; we render our own so it can update live.
	tooltip_text = ""
	_hover_timer = Timer.new()
	_hover_timer.one_shot = true
	_hover_timer.wait_time = ProjectSettings.get_setting("gui/timers/tooltip_delay_sec", _DEFAULT_DELAY)
	_hover_timer.timeout.connect(_show_tip)
	add_child(_hover_timer)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_dismiss)
	tree_exiting.connect(_dismiss)
	visibility_changed.connect(func() -> void: if not is_visible_in_tree(): _dismiss())

func _on_mouse_entered() -> void:
	# Arm the hover delay; the tooltip appears when it elapses.
	if not _text_for(Input.is_action_pressed("ui_verbose")).is_empty():
		_hover_timer.start()

func _dismiss() -> void:
	if _hover_timer != null:
		_hover_timer.stop()
	if _active == self:
		_active = null
		if is_instance_valid(_panel):
			_panel.visible = false

func _input(event: InputEvent) -> void:
	# Only the button whose tooltip is open refreshes, and only on the verbose key.
	if not (event is InputEventKey) or _active != self:
		return
	if event.is_action_pressed("ui_verbose") or event.is_action_released("ui_verbose"):
		_render(_text_for(event.is_action_pressed("ui_verbose")))

func _show_tip() -> void:
	var text: String = _text_for(Input.is_action_pressed("ui_verbose"))
	if text.is_empty():
		return
	_ensure_popup()
	_active = self
	_panel.visible = true
	_render(text)

## Sets the popup text and repositions it near the cursor, clamped on-screen.
func _render(text: String) -> void:
	if not is_instance_valid(_panel):
		return
	_label.text = text
	_panel.size = _panel.get_combined_minimum_size()
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var pos: Vector2 = get_viewport().get_mouse_position() + _CURSOR_OFFSET
	pos.x = clampf(pos.x, 0.0, maxf(0.0, viewport_size.x - _panel.size.x))
	pos.y = clampf(pos.y, 0.0, maxf(0.0, viewport_size.y - _panel.size.y))
	_panel.position = pos

## The tooltip text for the given verbose state.
func _text_for(verbose: bool) -> String:
	return verbose_tooltip if verbose and not verbose_tooltip.is_empty() else simple_tooltip

func _ensure_popup() -> void:
	if is_instance_valid(_layer) and is_instance_valid(_panel) and is_instance_valid(_label):
		return
	_layer = CanvasLayer.new()
	_layer.layer = 128  # above the HUD
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.visible = false
	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_label)
	_layer.add_child(_panel)
	get_tree().root.add_child(_layer)
