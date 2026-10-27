class_name SaveResume
extends Node

## Loads a SAVED GAME (SaveGame): once the scenario has booted, lays the save's snapshot over it
## (SimulationSnapshot) and hands the match to the player on the tick it was saved on.
## gdd/systems/commands/saved-games.md §Loading.
##
## The restore starts at the first frame after the navmesh's first build, when everything that
## arms or deploys on it has run: the world is held, the save's structure laid down
## (SimulationSnapshot.prepare), and SETTLE_FRAMES later, at the start of a frame and before
## anything else in it, its state laid over that. Then it checks the state against the save's
## digest, carries the save's recording on, points the camera where the player left it, gives
## back the control groups and takes the loading screen down. A digest that differs is reported —
## the snapshot missed something — but the match is handed over anyway.

## The match is the player's again. `a_matched`: whether the state matched the save's digest.
signal resumed(a_matched: bool)

## Ahead of the recorder and the order stream: the hand-over happens before the tick's orders.
const PRIORITY: int = OrderStream.START_OF_TICK_PRIORITY - 2
## Frames the held world waits between laying down the save's structure and its state: the
## navigation server takes up a spawned agent over its next steps (measured: two), and one that
## is not yet taken up stands still. One more, for margin; the wait is held, so it changes nothing.
const SETTLE_FRAMES: int = 3

var _scenario: Scenario
var _save: ReplayFile
var _is_booted: bool = false
var _is_done: bool = false
## Frames left before the state is laid over the structure; -1 until the structure is down.
var _settling: int = -1
var _overlay: CanvasLayer = null


func _init(a_scenario: Scenario = null, a_save: ReplayFile = null) -> void:
	_scenario = a_scenario
	_save = a_save
	name = "SaveResume"
	process_physics_priority = PRIORITY
	# Runs through a hold: an opening dialog of the rebuilt scene must not stop the restore.
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_overlay = _build_overlay()
	add_child(_overlay)
	_scenario.map.nav_manager.navmesh_ready.connect(
		func() -> void: _is_booted = true, CONNECT_ONE_SHOT
	)


func is_done() -> bool:
	return _scenario == null or _is_done


func _physics_process(_a_delta: float) -> void:
	if _is_done or not _is_booted:
		return
	var clock: SimulationClock = _clock()
	if _settling < 0:
		if clock != null:
			clock.hold(SimulationClock.REASON_RESTORE)
		SimulationSnapshot.prepare(_scenario, SaveGame.snapshot_of(_save))
		_settling = SETTLE_FRAMES
		return
	if _settling > 0:
		_settling -= 1
		return
	_is_done = true
	SimulationSnapshot.restore(_scenario, SaveGame.snapshot_of(_save))
	if clock != null and clock.is_held_by(SimulationClock.REASON_RESTORE):
		clock.release(SimulationClock.REASON_RESTORE)
	_scenario.recorder.adopt_records(SaveGame.replay_records_of(_save))
	var matched: bool = (
		SimulationDigest.of(_scenario) == str(_save.header.get(SaveGame.SAVE_DIGEST_KEY, ""))
	)
	if not matched:
		push_error(
			"SaveResume: the restored match differs from the save at tick %d" % _scenario.tick
		)
	_restore_camera()
	var controller: RTSController = SaveGame.controller_of(_scenario)
	if controller != null:
		controller.restore_control_groups(
			_save.header.get(SaveGame.CONTROL_GROUPS_KEY, []), _scenario
		)
	resumed.emit(matched)
	queue_free()


func _clock() -> SimulationClock:
	var manager: ScenarioTriggerManager = _scenario.trigger_manager()
	return manager.simulation_clock if manager != null else null


func _restore_camera() -> void:
	var at: Variant = _save.header.get(SaveGame.CAMERA_KEY)
	var camera := get_viewport().get_camera_3d() as RTSCamera3D if is_inside_tree() else null
	if camera != null and at is Array and (at as Array).size() == 2:
		camera.center_on(Vector2(float(at[0]), float(at[1])))


func _build_overlay() -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.name = "LoadingOverlay"
	layer.layer = 100
	var cover := ColorRect.new()
	cover.color = Color(0.05, 0.05, 0.06, 1.0)
	cover.set_anchors_preset(Control.PRESET_FULL_RECT)
	cover.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(cover)
	var label := Label.new()
	label.text = "Loading save…"
	label.set_anchors_preset(Control.PRESET_CENTER)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cover.add_child(label)
	return layer
