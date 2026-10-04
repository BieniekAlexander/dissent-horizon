class_name SimulationClock
extends Node

## Owns "is the game world simulating right now". Created by ScenarioTriggerManager._ready
## and reachable as `manager.simulation_clock`.
##
## The mechanism is `SceneTree.paused`, which suppresses `_physics_process` on every node
## whose process_mode is PAUSABLE/INHERIT. That maps exactly onto this game's split: all
## simulation lives in `_physics_process` (Commandable._update_state, Commander's
## ProductionQueue tick, Fog, BotBrain, Scenario.tick), while the player's own agency —
## selection, hotkeys, right-click orders, camera, HUD — lives in `_process` /
## `_unhandled_input`. So a hold freezes the world but leaves the player able to look
## around and issue orders, which is what a tutorial beat needs.
##
## The nodes that must keep running through a hold opt out by setting
## PROCESS_MODE_ALWAYS on themselves (RTSController, RTSCamera3D, ScenarioTriggerManager,
## and the tutorial HUD). That list is deliberately declared at each node rather than
## collected here: the clock should not have to go find the HUD.
##
## Holds are REASON-KEYED AND COUNTED rather than a single bool, because more than one
## system can want the world stopped at the same time (a dialog is open AND the tutorial
## is waiting for the player to issue a particular order). The world resumes only when the
## last hold is released — no system can stomp another's pause by "unpausing".

#region Signals
## Emitted whenever the aggregate pause state flips (not on every hold/release).
signal paused_changed(paused: bool)
#endregion

#region Constants
## Reason used by dialog popups that stop the world until acknowledged.
const REASON_DIALOG: StringName = &"dialog"
## Reason used by a tutorial beat waiting on a specific player input.
const REASON_TUTORIAL: StringName = &"tutorial"
## Reason used while the player has the HUD's help book open. Distinct from REASON_DIALOG so
## closing the book can never release a scripted dialog's hold, or vice versa.
const REASON_HELP: StringName = &"help"

## Reason used while the pause menu is up. Its own reason for the same purpose as REASON_HELP:
## a player who opens the pause menu over a scripted dialog and closes it again must not
## resume a world the dialog still wants stopped.
const REASON_PAUSE_MENU: StringName = &"pause_menu"

## Reason used while the debug playback control has the world paused (see PlaybackSpeed).
## Outlives the pause menu that took it: the world stays stopped once the menu closes.
const REASON_PLAYBACK_PAUSE: StringName = &"playback_pause"
#endregion

#region Properties
## reason -> outstanding hold count. Empty means the world is running.
var _holds: Dictionary = {}
#endregion


#region Public API
## Take a hold in `reason`'s name, freezing simulation. Re-entrant: two holders of the
## same reason each need to release before the world resumes.
func hold(a_reason: StringName) -> void:
	_holds[a_reason] = int(_holds.get(a_reason, 0)) + 1
	_apply()


## Drop one hold taken by `reason`. Releasing a reason that isn't held is a no-op (and a
## warning) rather than an error — a dialog dismissed twice shouldn't resume a world that
## another system still wants frozen.
func release(a_reason: StringName) -> void:
	var count: int = int(_holds.get(a_reason, 0))
	if count <= 0:
		push_warning("SimulationClock: released '%s' with no outstanding hold" % a_reason)
		return
	if count == 1:
		_holds.erase(a_reason)
	else:
		_holds[a_reason] = count - 1
	_apply()


## Drop every hold and resume. For scene teardown / test cleanup — prefer paired
## hold()/release() in gameplay code.
func clear() -> void:
	_holds.clear()
	_apply()


func is_paused() -> bool:
	return not _holds.is_empty()


func is_held_by(a_reason: StringName) -> bool:
	return int(_holds.get(a_reason, 0)) > 0


## Outstanding hold count for `reason` (0 when not held).
func hold_count(a_reason: StringName) -> int:
	return int(_holds.get(a_reason, 0))


#endregion


#region Private helpers
## Push the aggregate state onto the SceneTree and announce real transitions only.
func _apply() -> void:
	var want: bool = is_paused()
	# Not in the tree (a clock built standalone in a test): there is no tree to pause, so keep
	# the bookkeeping and skip the engine call. Guarded on is_inside_tree rather than a null
	# check on get_tree(), because get_tree() on an orphan node raises an engine error.
	if not is_inside_tree():
		return
	var tree: SceneTree = get_tree()
	if tree.paused == want:
		return
	tree.paused = want
	paused_changed.emit(want)


## Never leave the tree paused because the scenario went away mid-hold. get_tree() is still
## valid here — EXIT_TREE runs before the node is detached.
func _exit_tree() -> void:
	if _holds.is_empty():
		return
	var tree: SceneTree = get_tree()
	if tree != null and tree.paused:
		tree.paused = false
#endregion
