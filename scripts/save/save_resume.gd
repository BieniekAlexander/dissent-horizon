class_name SaveResume
extends Node

## Loads a SAVED GAME by re-simulating it (SaveGame): plays the save's orders back from the
## start, as fast as the machine allows, behind a loading screen, and hands the match to the
## player on the tick it was saved on. gdd/systems/commands/saved-games.md §Loading.
##
## On that tick, before anything else in it runs: checks the state against the save's digest,
## switches the order stream to live play, puts the speed back, points the camera where the
## player left it and takes the loading screen down. A digest that differs is reported — the
## build re-simulated the orders to a different world — but the match is handed over anyway.

## The match is the player's again. `a_matched`: whether the state matched the save's digest.
signal resumed(a_matched: bool)

## Ahead of the recorder and the order stream: the hand-over happens before the tick's orders.
const PRIORITY: int = OrderStream.START_OF_TICK_PRIORITY - 2

var _scenario: Scenario
var _save: ReplayFile
var _target_tick: int = 0
var _overlay: CanvasLayer = null
var _progress: Label = null


func _init(a_scenario: Scenario = null, a_save: ReplayFile = null) -> void:
	_scenario = a_scenario
	_save = a_save
	_target_tick = SaveGame.save_tick(a_save)
	name = "SaveResume"
	process_physics_priority = PRIORITY
	# Runs through a dialog's hold, as the stream does: a held world is still catching up.
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	PlaybackSpeed.set_uncapped()
	_overlay = _build_overlay()
	add_child(_overlay)


func is_done() -> bool:
	return _scenario == null or _scenario.tick >= _target_tick


func _process(_a_delta: float) -> void:
	if _progress != null and _target_tick > 0:
		_progress.text = (
			"Loading save… %d%%" % (100 * mini(_scenario.tick, _target_tick) / _target_tick)
		)


func _physics_process(_a_delta: float) -> void:
	if _scenario == null or _scenario.tick < _target_tick:
		return
	var matched: bool = (
		SimulationDigest.of(_scenario) == str(_save.header.get(SaveGame.SAVE_DIGEST_KEY, ""))
	)
	if not matched:
		push_error(
			"SaveResume: the re-simulated match differs from the save at tick %d" % _target_tick
		)
	_scenario.order_stream.go_live()
	PlaybackSpeed.reset()
	_restore_camera()
	resumed.emit(matched)
	queue_free()


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
	_progress = Label.new()
	_progress.text = "Loading save…"
	_progress.set_anchors_preset(Control.PRESET_CENTER)
	_progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cover.add_child(_progress)
	return layer
