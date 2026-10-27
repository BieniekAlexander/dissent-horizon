class_name SimulationClock
extends Node

## Owns "is the game world simulating right now". Created by ScenarioTriggerManager._ready
## and reachable as `manager.simulation_clock`.
##
## The mechanism is `SceneTree.paused`, which suppresses `_physics_process` on every node
## whose process_mode is PAUSABLE/INHERIT. That maps exactly onto this game's split: all
## simulation lives in `_physics_process` (Actor._update_state, Commander's
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

## Reason used while the pause menu is up (and with it the briefing and How to Play). Its own
## reason, distinct from REASON_DIALOG: a player who opens the pause menu over a scripted dialog
## and closes it again must not resume a world the dialog still wants stopped.
const REASON_PAUSE_MENU: StringName = &"pause_menu"

## Reason used while the debug playback control has the world paused (see PlaybackSpeed).
## Outlives the pause menu that took it: the world stays stopped once the menu closes.
const REASON_PLAYBACK_PAUSE: StringName = &"playback_pause"

## Reason used while a networked match waits for a peer's turn (OrderStream, Lockstep). Nothing
## is awaited from the player, so scenario conditions are not polled through it: how long it
## lasts differs per machine, and a poll per stalled frame would fire a repeating trigger a
## different number of times on each.
const REASON_NETWORK_WAIT: StringName = &"network_wait"

## Reason used from a scenario's first frame until its navmesh is first built (Scenario), so tick
## 0 is the same tick however the scene entered the tree.
const REASON_BOOT: StringName = &"boot"
#endregion

#region Properties
## reason -> outstanding hold count. Empty means the world is running.
var _holds: Dictionary = {}

## Frames the world has been held for, over every closed hold, and the engine frame the open
## hold began on (-1 when none is open). Static because the thing they track is: one SceneTree,
## one pause, one engine frame counter — whichever scenario's clock took the hold.
static var _frames_held: int = 0
static var _held_since_frame: int = -1
#endregion


#region Simulation frames
## The engine's physics frame count less every frame the world was held: the frame counter for
## simulation code that measures time in frames (a weapon's lock-on, stealth's detection,
## a cached path). Engine.get_physics_frames() keeps counting through a hold, so a hold of any
## length — a dialog, a network stall — would age those timers on one machine and not another.
## The frame a hold is taken on counts as held, and the frame it is released on as running,
## which is right for a hold taken and released at the start of a frame (OrderStream's).
static func physics_frame() -> int:
	var now: int = Engine.get_physics_frames()
	var open: int = now - _held_since_frame if _held_since_frame >= 0 else 0
	return now - _frames_held - open


static func _close_held_interval() -> void:
	if _held_since_frame >= 0:
		_frames_held += Engine.get_physics_frames() - _held_since_frame
		_held_since_frame = -1


#endregion


#region Public API
## Take a hold in `reason`'s name, freezing simulation. Re-entrant: two holders of the
## same reason each need to release before the world resumes.
func hold(a_reason: StringName) -> void:
	if _refuses(a_reason):
		return
	_holds[a_reason] = int(_holds.get(a_reason, 0)) + 1
	_apply()


## Drop one hold taken by `reason`. Releasing a reason that isn't held is a no-op (and a
## warning) rather than an error — a dialog dismissed twice shouldn't resume a world that
## another system still wants frozen.
func release(a_reason: StringName) -> void:
	if _refuses(a_reason):
		return
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
## In a networked match only the network wait holds the world: every other hold — the pause
## menu, a playback pause, a scripted dialog — would stop this machine alone and
## desync the match, so it is taken (and released) as if it had been, and the world runs on. The
## pause menu is then the overlay netplay.md §Rules asks for.
func _refuses(a_reason: StringName) -> bool:
	if a_reason == REASON_NETWORK_WAIT:
		return false
	var scenario: Scenario = Scenario.of(self)
	return scenario != null and scenario.is_networked()


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
	# SceneTree.paused stops the physics server but not the navigation server, whose avoidance
	# would keep moving pieces through a hold (AvoidanceAgent3D keeps every agent registered).
	NavigationServer3D.set_active(not want)
	if want:
		_held_since_frame = Engine.get_physics_frames()
	else:
		_close_held_interval()
	paused_changed.emit(want)


## Never leave the tree paused because the scenario went away mid-hold. get_tree() is still
## valid here — EXIT_TREE runs before the node is detached.
func _exit_tree() -> void:
	# Closed whatever the tree's state: SceneManager unpauses it directly when it leaves a scene.
	_close_held_interval()
	NavigationServer3D.set_active(true)
	if _holds.is_empty():
		return
	var tree: SceneTree = get_tree()
	if tree != null and tree.paused:
		tree.paused = false
#endregion
