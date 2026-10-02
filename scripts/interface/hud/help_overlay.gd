@tool
class_name HelpOverlay
extends Control

## Two mutually exclusive panels of player-facing copy, swapped by holding `show_help`:
##
##   * the HINT — small, parked above the minimap, up whenever the key is NOT held. The
##     always-on line: one short sentence saying what to do next.
##   * the HELP — large, centred on screen, up only WHILE the key is held. The fuller
##     reference the hint points at.
##
## Never both, never neither — the hold decides which one is drawn. Hold-to-reveal rather
## than a toggle so there is no state to get stuck in: release and the screen is clear
## again, so a player can't lose the match behind a panel they forgot they opened. Same
## idiom as the verbose tooltips (hold `ui_verbose`).
##
## A third, independent line sits above the hint: the DEBUG HINT, telling the player how to
## bring up the debug view. Up only in a session that allows debugging (see DebugMode), and
## only while the view is down — once it is up, the hint has done its job.
##
## The LAYOUT is authored, in scenes/interface/help_overlay.tscn, and instanced into the
## player HUD (scenes/player.tscn). This script owns only which panel is visible and what
## text it carries; where the panels sit, how big they are and how they're styled are all
## inspector work. Same split as ObjectiveView, and everything here is looked up by
## scene-unique name, so the tree inside that scene can be rearranged freely.
##
## Copy is authored on the two exported strings and supports `{{ action }}` placeholders
## exactly as DialogPage does — write `{{ show_help }}` and the player reads "F4", from
## whatever the action is bound to right now. See InputPrompt.

#region Constants
## The hold that swaps hint for help.
##
## POLLED (Input.is_action_pressed) rather than latched off pressed/released events: a poll
## cannot get stuck showing the help panel when a release goes missing — window focus lost
## mid-hold, or a focused Control eating the key — which a latch can. It is also why
## the purchase modifiers are polled at purchase time rather than latched (see RTSController).
const ACTION: StringName = &"show_help"
#endregion

#region Properties
@export_category("Copy")
## The always-visible line above the minimap, shown whenever ACTION is NOT held. BBCode is
## enabled; supports `{{ action }}` placeholders (see InputPrompt).
@export_multiline var hint_text: String = "":
	set(value):
		hint_text = value
		_refresh()

## The large centred panel, shown only WHILE ACTION is held. BBCode is enabled; supports
## `{{ action }}` placeholders (see InputPrompt).
@export_multiline var help_text: String = "":
	set(value):
		help_text = value
		_refresh()

## The line above the hint, shown while the session allows the debug view and it is not up.
## BBCode is enabled; supports `{{ action }}` placeholders (see InputPrompt).
@export_multiline var debug_hint_text: String = "":
	set(value):
		debug_hint_text = value
		_refresh()

@onready var _hint_panel: Control = %HintPanel
@onready var _hint_label: RichTextLabel = %HintText
@onready var _help_panel: Control = %HelpPanel
@onready var _help_label: RichTextLabel = %HelpText
@onready var _debug_hint_panel: Control = %DebugHintPanel
@onready var _debug_hint_label: RichTextLabel = %DebugHintText

## Whether ACTION was held on the previous frame. Visibility and text are recomputed on the
## EDGE rather than every frame: _process runs at display rate and InputPrompt.format walks
## a RegEx over the copy. Re-resolving each time a panel comes UP still keeps DialogPage's
## guarantee that a prompt shows what the player would press today, so a rebinding
## mid-match lands on the next reveal.
var _held: bool = false

## Whether the debug hint was up on the previous frame; edge-triggered for the same reason
## as `_held`.
var _is_debug_hint_up: bool = false
#endregion


#region Lifecycle
func _ready() -> void:
	# The scenario layer pauses the tree to hold the simulation (see SimulationClock). An
	# overlay that froze with it would be unreachable exactly when a player stopped by a
	# scripted beat wants to read it. Same declaration as RTSController / ScenarioDialogView.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Covers the whole viewport, so it must never eat a click meant for the world.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_refresh()
	if Engine.is_editor_hint():
		# Leave the authored `visible` flags alone in the editor, so both panels can be shown
		# and positioned independently while laying the scene out.
		return
	_held = Input.is_action_pressed(ACTION)
	_apply_visibility()
	_is_debug_hint_up = _should_show_debug_hint()
	_apply_debug_hint_visibility()


func _process(_a_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var is_debug_hint_up: bool = _should_show_debug_hint()
	if is_debug_hint_up != _is_debug_hint_up:
		_is_debug_hint_up = is_debug_hint_up
		_refresh()
		_apply_debug_hint_visibility()
	var held: bool = Input.is_action_pressed(ACTION)
	if held == _held:
		return
	_held = held
	_refresh()
	_apply_visibility()


#endregion


#region Public API
## True while the large centred panel is the one on screen (ACTION held). The hint is up
## whenever this is false: the two are never both up, and never both down.
func is_showing_help() -> bool:
	return _held


## The hint copy with its `{{ action }}` placeholders resolved — what the player reads.
func resolved_hint_text() -> String:
	return InputPrompt.format(hint_text)


## The help copy with its `{{ action }}` placeholders resolved — what the player reads.
func resolved_help_text() -> String:
	return InputPrompt.format(help_text)


## True while the debug hint is the line on screen above the hint.
func is_showing_debug_hint() -> bool:
	return _is_debug_hint_up


## The debug hint copy with its `{{ action }}` placeholders resolved — what the player reads.
func resolved_debug_hint_text() -> String:
	return InputPrompt.format(debug_hint_text)


#endregion


#region Internal
## Push the authored copy onto the labels, resolving control placeholders on the way. The
## exported strings keep the placeholders they were written with; only the labels get the
## bindings, so a re-resolve always reflects the CURRENT InputMap.
##
## Guarded because the property setters fire while the scene is still loading, before
## @onready has resolved anything.
func _refresh() -> void:
	if _hint_label == null or _help_label == null:
		return
	_hint_label.text = resolved_hint_text()
	_help_label.text = resolved_help_text()
	if _debug_hint_label != null:
		_debug_hint_label.text = resolved_debug_hint_text()


## Exactly one panel is up. Both flags are driven from `_held` alone, so there is no state
## in which they can disagree.
func _apply_visibility() -> void:
	if _hint_panel == null or _help_panel == null:
		return
	_hint_panel.visible = not _held
	_help_panel.visible = _held


func _should_show_debug_hint() -> bool:
	return DebugMode.is_allowed() and not DebugMode.is_active()


func _apply_debug_hint_visibility() -> void:
	if _debug_hint_panel == null:
		return
	_debug_hint_panel.visible = _is_debug_hint_up
#endregion
