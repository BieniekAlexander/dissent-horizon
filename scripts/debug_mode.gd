class_name DebugMode
extends Node

## The session's debug view: fog lifted, the minimap revealed, command labels over units, the
## bot overlay and the cursor readout. Every one of those asks `DebugMode.is_active()`.
##
## Two switches, owned by two people. `Scenario.debug_allowed` is the AUTHOR's — whether this
## session may show debug information at all. TOGGLE_ACTION is the PLAYER's — whether it is
## showing now. Active means both.
##
## A toggle rather than a hold, so the view can be left up while both hands are on the game.
##
## Created by Scenario._ready as a child. The node exists only to receive the key; the state
## is static because its readers — every Commandable, each Fog, the minimap, HUD labels — have
## no path to their Scenario, and one session runs at a time (as with Fog.active_commander_id).

## The key that shows and hides the debug view.
const TOGGLE_ACTION: StringName = &"show_debug_info"

## Whether the running session permits the debug view. Written by `configure` only.
static var _is_allowed: bool = false

## Whether the player has toggled the view on. Meaningless unless `_is_allowed`.
static var _is_shown: bool = false


## True while debug information should be drawn: the session allows it and it is toggled on.
static func is_active() -> bool:
	return _is_allowed and _is_shown


## True when the session permits the debug view, whether or not it is showing.
static func is_allowed() -> bool:
	return _is_allowed


## Start a session's debug state: permitted or not, and hidden either way.
static func configure(is_permitted: bool) -> void:
	_is_allowed = is_permitted
	_is_shown = false


## Flip the view. Ignored in a session that does not allow it, so a disallowed session can
## never be left holding a latent "shown" that a later `configure` would have to undo.
static func toggle() -> void:
	if _is_allowed:
		_is_shown = not _is_shown


func _ready() -> void:
	# The scenario layer pauses the tree to hold the simulation (see SimulationClock); the
	# debug view is most wanted exactly then.
	process_mode = Node.PROCESS_MODE_ALWAYS


func _exit_tree() -> void:
	# A session's permission must not outlive it: the next scene, or the next test, starts
	# from nothing.
	configure(false)


func _unhandled_input(a_event: InputEvent) -> void:
	if a_event.is_action_pressed(TOGGLE_ACTION) and not a_event.is_echo():
		toggle()
		get_viewport().set_input_as_handled()
