class_name VerboseTooltipButton
extends Button

## A Button with two tooltip variants shown through a CUSTOM popup rather than
## Godot's built-in tooltip. The built-in tooltip captures its text when it opens
## on hover and can't be refreshed mid-hover; this custom popup can, so pressing
## or releasing the "ui_verbose" action (/) while the tooltip is open swaps it
## live between `simple_tooltip` and `verbose_tooltip`. Buttons with no verbose
## text just keep showing the simple one.
##
## EVERY button of this class shows something on hover. A blank `simple_tooltip` is
## treated as an authoring bug, not as "no tooltip": it is replaced by MISSING_TOOLTIP
## and reported with push_error, so an undescribed button is loud in the editor's error
## panel and visibly unfinished in-game rather than silently featureless. The verbose
## variant stays optional — a button whose one line says everything has nothing longer
## to say.

## Stand-in shown (and pushed as an error) when a button reaches the player with no
## simple tooltip. Deliberately reads as a bug rather than as copy.
const MISSING_TOOLTIP: String = "TODO fill out this tooltip"

## Tooltip shown normally. Assigning "" substitutes MISSING_TOOLTIP and reports it;
## see the class comment.
var simple_tooltip: String = "":
	set(value):
		if value.is_empty():
			push_error("VerboseTooltipButton '%s' was given an empty simple tooltip" % name)
			simple_tooltip = MISSING_TOOLTIP
		else:
			simple_tooltip = value

## Tooltip shown while the "ui_verbose" action (/) is held. Optional: empty means the
## simple one is shown in both states.
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

#region Availability overlay
## Two OVERLAY labels a command button can carry, both filling the whole button rect and
## aligning their text inside it. Full-rect + alignment rather than a computed corner box,
## because a sized-and-offset overlay is exactly the bug that put every status bar BELOW its
## CommandableCard for months (see CLAUDE.md §Seeing the HUD without a screen) — there is no
## arithmetic here to get wrong.
##
##   charges  "2/3", bottom-right. Drawn only above a capacity of one: "1/1" says nothing a
##            lit button does not already say.
##   timer    seconds to the next charge, centred. It is the answer to the only question a
##            greyed ability raises — not "why", but "how long".
##
## Both are created lazily, so a button that never carries either costs nothing.
const CHARGE_FONT_SIZE: int = 11
const TIMER_FONT_SIZE: int = 15
const TIMER_COLOR: Color = Color(1.0, 1.0, 1.0, 0.92)
const CHARGE_COLOR: Color = Color(1.0, 1.0, 1.0, 0.8)

var _charge_label: Label = null
var _timer_label: Label = null
## The lit edge a TOGGLE draws while it is on (CommandButtonState.is_toggled_on). Along the top,
## and thin, so it qualifies the button rather than competing with its label.
var _toggle_edge: ColorRect = null
const TOGGLE_EDGE_HEIGHT: float = 3.0
const TOGGLE_EDGE_COLOR: Color = Color(0.55, 0.85, 1.0)

## Show `a_state` on this button: tint, charge pips and countdown together, so the three can
## never disagree about what the button is saying.
func show_availability(a_state: CommandButtonState) -> void:
	modulate = a_state.tint()
	_overlay(true).text = "%d/%d" % [a_state.charges, a_state.max_charges] \
		if a_state.shows_charges() else ""
	# One decimal below ten seconds, whole seconds above it: a long cooldown ticking in
	# hundredths is noise, and a short one rounded to a whole second reads as stalled.
	var seconds: float = a_state.recharge_seconds()
	_overlay(false).text = ("%.1f" % seconds if seconds < 10.0 else "%d" % roundi(seconds)) \
		if a_state.shows_timer() else ""
	if a_state.is_toggled_on or _toggle_edge != null:
		_toggle_edge_rect().visible = a_state.is_toggled_on

## The toggle edge, created on first use.
func _toggle_edge_rect() -> ColorRect:
	if _toggle_edge == null:
		_toggle_edge = ColorRect.new()
		_toggle_edge.color = TOGGLE_EDGE_COLOR
		_toggle_edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_toggle_edge.set_anchors_preset(Control.PRESET_TOP_WIDE)
		_toggle_edge.offset_bottom = TOGGLE_EDGE_HEIGHT
		add_child(_toggle_edge)
	return _toggle_edge

## The overlay label, created on first use. `a_is_charges` picks which of the two.
func _overlay(a_is_charges: bool) -> Label:
	var existing: Label = _charge_label if a_is_charges else _timer_label
	if existing != null:
		return existing
	var label := Label.new()
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	# The button owns the click; an overlay that could take it would make a command button
	# dead in exactly the corner the player can see something written.
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size",
		CHARGE_FONT_SIZE if a_is_charges else TIMER_FONT_SIZE)
	label.add_theme_color_override("font_color", CHARGE_COLOR if a_is_charges else TIMER_COLOR)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 3)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if a_is_charges \
		else HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM if a_is_charges \
		else VERTICAL_ALIGNMENT_CENTER
	add_child(label)
	if a_is_charges:
		_charge_label = label
	else:
		_timer_label = label
	return label
#endregion

func _ready() -> void:
	# Suppress the built-in tooltip; we render our own so it can update live.
	tooltip_text = ""
	# A HUD button must never HOLD keyboard focus. A focused Control consumes the keys the
	# game is listening for before _unhandled_input ever sees them — Tab would move focus
	# rather than flip the command card, and Space (the fog debug view) and Enter would
	# re-press whichever button was last clicked. Clicking a button to give an order would
	# otherwise silently disarm part of the keyboard until the player clicked the world.
	focus_mode = Control.FOCUS_NONE
	# Catches the button nobody ever assigned a tooltip to — the setter only fires on an
	# explicit empty assignment, so entering the tree is the last moment to notice.
	if simple_tooltip.is_empty():
		push_error("VerboseTooltipButton '%s' entered the HUD with no tooltip" % name)
		simple_tooltip = MISSING_TOOLTIP
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

func _input(a_event: InputEvent) -> void:
	# Only the button whose tooltip is open refreshes, and only on the verbose key.
	if not (a_event is InputEventKey) or _active != self:
		return
	if a_event.is_action_pressed("ui_verbose") or a_event.is_action_released("ui_verbose"):
		_render(_text_for(a_event.is_action_pressed("ui_verbose")))

func _show_tip() -> void:
	var text: String = _text_for(Input.is_action_pressed("ui_verbose"))
	if text.is_empty():
		return
	_ensure_popup()
	_active = self
	_panel.visible = true
	_render(text)

## Sets the popup text and repositions it near the cursor, clamped on-screen.
func _render(a_text: String) -> void:
	if not is_instance_valid(_panel):
		return
	_label.text = a_text
	_panel.size = _panel.get_combined_minimum_size()
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var pos: Vector2 = get_viewport().get_mouse_position() + _CURSOR_OFFSET
	pos.x = clampf(pos.x, 0.0, maxf(0.0, viewport_size.x - _panel.size.x))
	pos.y = clampf(pos.y, 0.0, maxf(0.0, viewport_size.y - _panel.size.y))
	_panel.position = pos

## The tooltip text for the given verbose state.
func _text_for(a_verbose: bool) -> String:
	return verbose_tooltip if a_verbose and not verbose_tooltip.is_empty() else simple_tooltip

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
