extends Node

## Owns every change of scene: the title screen opening a scenario, and a scenario handing
## the player back to the title screen — whether that came from the pause menu or from a
## victory dialog's "return to menu" button.
##
## An AUTOLOAD, which is Godot's standard shape for this (the engine's own singleton docs use
## a scene switcher as the worked example). A scene swap OUTLIVES the scene that asked for
## it: the requester is freed as part of the transition, so it cannot be the thing that owns
## it. A global that is never unloaded can.
##
## ── Why this exists, rather than each caller writing change_scene_to_* itself ──
##
## `SceneTree.paused` belongs to the TREE, not to the scene, so it SURVIVES a scene change.
## Returning to the menu from a pause menu — which pauses by definition — would hand the
## player a title screen that is still paused, and a paused tree suppresses _process on every
## PROCESS_MODE_INHERIT node, including its buttons. The menu would draw and then ignore
## every click, with nothing left in the new scene able to release the pause, because the
## SimulationClock that took the hold died with the scenario that owned it.
##
## Clearing the pause is therefore part of changing scene, and belongs wherever the change is
## made — once, here, instead of at each of the three call sites.

#region Constants
## The title screen. A const rather than an export: an autoload has no scene to be
## configured in, and "where is the main menu" is a fact about the project.
const MAIN_MENU_SCENE: String = "res://scenes/menu/main_menu.tscn"
#endregion

#region Signals
## Emitted just before the tree is asked to swap, with the target's resource path. Lets
## anything observe navigation without hooking the SceneTree — and lets tests assert that a
## button asked to navigate without actually performing the swap.
signal scene_change_requested(path: String)
## Emitted by quit_game just before the application closes.
signal quit_requested
#endregion

#region Properties
## Set by a test so quit_game announces without quitting.
var suppress_quit: bool = false
#endregion


#region Public API
## Leave whatever is running and return to the title screen. The one way back: both the
## pause menu and the victory dialog route here, so there is a single description of what
## "return to the main menu" does.
func to_main_menu() -> Error:
	return go_to_file(MAIN_MENU_SCENE)


## Swap to the scene at `path`. Reports and stays put when there is nothing there — a typo'd
## path would otherwise blank the screen with no indication of why.
func go_to_file(a_path: String) -> Error:
	if not ResourceLoader.exists(a_path):
		push_error("SceneManager: no scene at '%s'; staying put." % a_path)
		return ERR_FILE_NOT_FOUND
	_resume()
	scene_change_requested.emit(a_path)
	var result: Error = get_tree().change_scene_to_file(a_path)
	if result != OK:
		push_error("SceneManager: could not open '%s': %s" % [a_path, error_string(result)])
	return result


## Swap to an already-loaded scene — what the title screen's buttons use, since a
## ScenarioEntry holds a PackedScene rather than a path.
func go_to_packed(a_scene: PackedScene) -> Error:
	if a_scene == null:
		push_error("SceneManager: asked to open a null scene; staying put.")
		return ERR_INVALID_PARAMETER
	_resume()
	scene_change_requested.emit(a_scene.resource_path)
	var result: Error = get_tree().change_scene_to_packed(a_scene)
	if result != OK:
		push_error(
			"SceneManager: could not open '%s': %s" % [a_scene.resource_path, error_string(result)]
		)
	return result


## Swap to `a_scene`, a node built at runtime and not yet in the tree — a skirmish the lobby
## assembled (SkirmishLauncher). The tree takes ownership; on a refused swap it is freed here.
func go_to_node(a_scene: Node) -> Error:
	if a_scene == null:
		push_error("SceneManager: asked to open a null node; staying put.")
		return ERR_INVALID_PARAMETER
	_resume()
	scene_change_requested.emit(a_scene.scene_file_path)
	var result: Error = get_tree().change_scene_to_node(a_scene)
	if result != OK:
		push_error("SceneManager: could not open a built scene: %s" % error_string(result))
		a_scene.free()
	return result


## Close the application. Announced first, like a scene change, so a test can see the request
## without the tree actually quitting.
func quit_game() -> void:
	quit_requested.emit()
	if not suppress_quit:
		get_tree().quit()


## Play the replay at `a_path`, replacing the whole tree with its scenario set up to play it
## back. Returns why it cannot be played — another version, a recording debug mode ended, no such
## scenario — or "" once the swap is asked for. The start screen shows the refusal.
## gdd/systems/commands/recording-and-replay.md §Watching.
func play_replay(a_path: String) -> String:
	var prepared: Dictionary = ReplayLibrary.prepare_playback(a_path)
	if prepared.has("refusal"):
		return prepared["refusal"]
	var scenario: Scenario = prepared["scenario"]
	_resume()
	scene_change_requested.emit(scenario.scene_file_path)
	var result: Error = get_tree().change_scene_to_node(scenario)
	if result != OK:
		scenario.free()
		return "Could not open the replay: %s." % error_string(result)
	return ""


#endregion


#region Internal
## Drop the tree-wide pause before leaving. Written straight onto the SceneTree rather than
## released through a SimulationClock: the clock belongs to the scenario being torn down, its
## holds are about to become meaningless, and the incoming scene must start running whatever
## state the outgoing one happened to be in. See the class comment.
func _resume() -> void:
	var tree: SceneTree = get_tree()
	if tree != null:
		tree.paused = false
#endregion
