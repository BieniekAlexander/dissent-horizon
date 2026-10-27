extends Node

## SAVE AND LOAD A LONG MATCH, MANY TIMES: a bot skirmish built from a fixed recipe, as the
## determinism probe builds one (tools/netplay/determinism_probe.gd), played straight through and
## saved at every checkpoint; then each save is loaded and played on, and must be the same match
## the straight run played — the restored world field for field at the load and some ticks on,
## and digest for digest up to the horizon. What a snapshot misses, a long fought match finds.
## gdd/systems/commands/saved-games.md §The snapshot.
##
## Run:
##   godot --headless --path . --fixed-fps 30 tools/snapshot/save_load_probe.tscn -- \
##       --out=/abs/dir [--ticks=9000] [--every=1500] [--horizon=300] [--seed=20261014]
## Writes `--out`/report.json (and the saves), prints a line per checkpoint, and exits non-zero
## when any checkpoint failed.
##
## `--scene=res://….tscn` plays that authored scenario instead of a skirmish — a mission, to cover
## triggers, dialogs and tactics. Nobody plays it: every scripted dialog is answered with its first
## option, as a recorded order, DIALOG_ANSWER_FRAMES after it opens.

const DEFAULT_RECIPE_SEED: int = 20261014
const DEFAULT_TICKS: int = 9000
const DEFAULT_EVERY: int = 1500
## How long each loaded save is played on and compared.
const DEFAULT_HORIZON: int = 300
const COMPARE_EVERY_TICKS: int = 30
## The result of a checkpoint the match could not be saved at.
const SKIPPED: String = "skipped"
## When, after the load, the two worlds are compared whole again.
const RECAPTURE_AFTER_TICKS: int = 30
const PLAYERS: int = 2
## A stage that stops advancing gives up rather than hangs.
const GIVE_UP_SECONDS: float = 3600.0
## For this many ticks after each checkpoint, every piece's exact position and velocity is compared
## every tick: a drift below the digest's rounding is named on the tick it starts.
const DENSE_TICKS: int = 12
## How long an open dialog waits for its answer, in frames. The world is held meanwhile, so the
## answer lands on the same tick however long it waits.
const DIALOG_ANSWER_FRAMES: int = 10
## How many differing fields a checkpoint's report lists.
const DIFFS_REPORTED: int = 40

enum Stage { STRAIGHT, LOADING, PLAYING_ON, DONE }

var _out: String = ""
var _ticks: int = DEFAULT_TICKS
var _every: int = DEFAULT_EVERY
var _horizon: int = DEFAULT_HORIZON
var _recipe_seed: int = DEFAULT_RECIPE_SEED
## The first checkpoint saved; earlier ones are skipped, to look at one late in a match.
var _first: int = 0
## An authored scenario to play instead of a skirmish, or "".
var _scene: String = ""
## Open dialog serial → frames it has waited for its answer.
var _waiting_dialogs: Dictionary = {}
var _recipe: Dictionary = {}
var _stage: Stage = Stage.STRAIGHT
var _scenario: Scenario = null
var _started_msec: int = 0
var _last_tick: int = -1
## Straight run: state strings by tick, and whole captures by tick, for the comparisons.
var _states: Dictionary = {}
var _raw: Dictionary = {}
var _captures: Dictionary = {}
## The checkpoints still to load, and the one playing on.
var _pending: Array[int] = []
var _checkpoint: int = -1
var _report: Array[Dictionary] = []
var _current: Dictionary = {}


func _ready() -> void:
	# Sample after every piece has ticked, so a sample is the state the tick left behind.
	process_physics_priority = 1000
	# Runs through a hold, or it could not answer the dialog holding the world.
	process_mode = Node.PROCESS_MODE_ALWAYS
	for argument: String in OS.get_cmdline_user_args():
		var pair: PackedStringArray = argument.trim_prefix("--").split("=", true, 1)
		if pair.size() != 2:
			continue
		match pair[0]:
			"out":
				_out = pair[1]
			"ticks":
				_ticks = int(pair[1])
			"every":
				_every = int(pair[1])
			"horizon":
				_horizon = int(pair[1])
			"seed":
				_recipe_seed = int(pair[1])
			"first":
				_first = int(pair[1])
			"scene":
				_scene = pair[1]
	if _out.is_empty():
		push_error("save_load_probe: no --out directory given.")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(_out)
	_started_msec = Time.get_ticks_msec()
	var setup := SkirmishSetup.new(PLAYERS)
	setup.human_plays_first_slot = false
	setup.set_team(0, 1)
	setup.set_team(1, 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = _recipe_seed
	_recipe = setup.recipe(rng)
	_launch_straight()


func _physics_process(_a_delta: float) -> void:
	if _stage == Stage.DONE:
		return
	if Time.get_ticks_msec() - _started_msec > int(GIVE_UP_SECONDS * 1000.0):
		_finish("gave up")
		return
	if _scenario == null or not _scenario.is_inside_tree():
		return
	if _stage != Stage.LOADING:
		_answer_dialogs()
	var tick: int = _scenario.tick
	if tick == _last_tick:
		return
	_last_tick = tick
	match _stage:
		Stage.STRAIGHT:
			_sample_straight(tick)
		Stage.PLAYING_ON:
			_compare(tick)


func _launch_straight() -> void:
	if not _scene.is_empty():
		_scenario = (load(_scene) as PackedScene).instantiate() as Scenario
		get_tree().root.add_child.call_deferred(_scenario)
		_make_current.call_deferred(_scenario)
		return
	var built: Dictionary = SkirmishLauncher.launch(_recipe)
	if built.has("refusal"):
		_finish("launch: %s" % built["refusal"])
		return
	_scenario = built["scenario"]
	get_tree().root.add_child.call_deferred(_scenario)
	_make_current.call_deferred(_scenario)


## Make `a_scenario` the tree's current scene, as SceneManager does: scene-placed pieces find
## their map through it (Entity._auto_initialize).
func _make_current(a_scenario: Scenario) -> void:
	get_tree().current_scene = a_scenario


## Answer every scripted dialog that has waited long enough, with its first option, on the order
## stream as a player would.
func _answer_dialogs() -> void:
	var manager: ScenarioTriggerManager = _scenario.trigger_manager()
	if manager == null:
		return
	for serial: int in manager._open_dialogs.keys():
		var waited: int = int(_waiting_dialogs.get(serial, 0)) + 1
		_waiting_dialogs[serial] = waited
		if waited == DIALOG_ANSWER_FRAMES:
			var player: Commander = _scenario.local_player()
			_scenario.order_stream.submit(
				PlayerOrder.new(
					PlayerOrder.Kind.DIALOG,
					player.id if player != null else 0,
					{"dialog": serial, "secondary": false}
				)
			)


func _sample_straight(a_tick: int) -> void:
	if a_tick % COMPARE_EVERY_TICKS == 0:
		_states[a_tick] = SimulationDigest.state_string(_scenario)
	var since: int = a_tick % _every
	if a_tick > _every / 2 and since <= DENSE_TICKS:
		_raw[a_tick] = _raw_positions()
	if a_tick > 0 and since == 0 and a_tick < _ticks and a_tick >= _first:
		var refusal: String = SaveGame.refusal_to_save(_scenario)
		if refusal.is_empty():
			_scenario.request_save(_save_path(a_tick))
			_pending.append(a_tick)
			print("save_load_probe: saved at tick %d" % a_tick)
		else:
			# Not a failure: a match that has ended cannot be saved, and a checkpoint past it
			# has nothing to check.
			_report.append({"checkpoint": a_tick, "result": SKIPPED, "reason": refusal})
			print("save_load_probe: tick %d not saved: %s" % [a_tick, refusal])
	if a_tick > _every and since == RECAPTURE_AFTER_TICKS:
		_captures[a_tick] = SnapshotDiff.normalised(SimulationSnapshot.capture(_scenario))
	if a_tick >= _ticks:
		_drop_scenario()
		_load_next()


func _load_next() -> void:
	if _pending.is_empty():
		_finish("")
		return
	_checkpoint = _pending.pop_front()
	_current = {"checkpoint": _checkpoint, "result": "", "restore_diffs": [], "later_diffs": []}
	var path: String = _save_path(_checkpoint)
	var built: Dictionary = SaveGame.prepare_resume(path)
	if built.has("refusal"):
		_close_checkpoint("refused: %s" % built["refusal"])
		_load_next()
		return
	_scenario = built["scenario"]
	_stage = Stage.LOADING
	_waiting_dialogs.clear()
	_last_tick = -1
	var save: ReplayFile = ReplayFile.read(path)
	get_tree().root.add_child(_scenario)
	_make_current(_scenario)
	(_scenario.get_node("SaveResume") as SaveResume).resumed.connect(
		func(_m: bool) -> void: _on_resumed(save), CONNECT_ONE_SHOT
	)


func _on_resumed(a_save: ReplayFile) -> void:
	var found: Array[String] = SnapshotDiff.differences(
		SnapshotDiff.normalised(SimulationSnapshot.capture(_scenario)),
		SnapshotDiff.normalised(SaveGame.snapshot_of(a_save)),
		SnapshotDiff.SERVER_READS
	)
	_current["restore_diffs"] = found.slice(0, DIFFS_REPORTED)
	_current["restore_diff_count"] = found.size()
	_stage = Stage.PLAYING_ON


func _compare(a_tick: int) -> void:
	if _raw.has(a_tick) and not _current.has("raw_drift"):
		var now: Dictionary = _raw_positions()
		var expected: Dictionary = _raw[a_tick]
		var differing: Array = []
		for serial: int in expected:
			if now.get(serial) != expected[serial]:
				differing.append(serial)
		if not differing.is_empty() or now.size() != expected.size():
			_current["raw_drift"] = "tick %d: pieces %s" % [a_tick, str(differing.slice(0, 12))]
	if a_tick - _checkpoint == RECAPTURE_AFTER_TICKS and _captures.has(a_tick):
		var found: Array[String] = SnapshotDiff.differences(
			SnapshotDiff.normalised(SimulationSnapshot.capture(_scenario)), _captures[a_tick]
		)
		_current["later_diffs"] = found.slice(0, DIFFS_REPORTED)
		_current["later_diff_count"] = found.size()
	if _states.has(a_tick) and not _current.has("drift"):
		var drift: String = SnapshotDiff.first_state_difference(
			SimulationDigest.state_string(_scenario), _states[a_tick]
		)
		if not drift.is_empty():
			_current["drift"] = "drifted at tick %d: %s" % [a_tick, drift]
	# A drift found, the match plays on to the whole-world comparison, which names what differs.
	var is_compared: bool = a_tick - _checkpoint >= RECAPTURE_AFTER_TICKS
	if a_tick >= mini(_checkpoint + _horizon, _ticks) or (_current.has("drift") and is_compared):
		_close_checkpoint(str(_current.get("drift", "")))
		_next_checkpoint()


func _next_checkpoint() -> void:
	_drop_scenario()
	_load_next()


func _close_checkpoint(a_failure: String) -> void:
	var is_clean: bool = (
		a_failure.is_empty()
		and int(_current.get("restore_diff_count", 0)) == 0
		and int(_current.get("later_diff_count", 0)) == 0
	)
	_current["result"] = (
		"ok" if is_clean else (a_failure if not a_failure.is_empty() else "fields differ")
	)
	_report.append(_current)
	print(
		(
			"save_load_probe: checkpoint %d: %s (restore %d, later %d fields differ)"
			% [
				_checkpoint,
				_current["result"],
				int(_current.get("restore_diff_count", 0)),
				int(_current.get("later_diff_count", 0)),
			]
		)
	)


## Every piece's exact position and velocity, by serial: the bits, not a rounding.
func _raw_positions() -> Dictionary:
	var out: Dictionary = {}
	for entity: Entity in _scenario.stepper.entities():
		# A piece held off the tree has no global position, and keeps its local one.
		var p: Vector3 = entity.global_position if entity.is_inside_tree() else entity.position
		var v: Vector3 = entity.velocity
		out[entity.spawn_serial] = PackedFloat64Array([p.x, p.y, p.z, v.x, v.y, v.z])
	return out


func _drop_scenario() -> void:
	if _scenario != null and is_instance_valid(_scenario):
		_scenario.get_parent().remove_child(_scenario)
		_scenario.free()
	_scenario = null


func _save_path(a_tick: int) -> String:
	return _out.path_join("checkpoint_%d.sav" % a_tick)


func _finish(a_error: String) -> void:
	_stage = Stage.DONE
	_drop_scenario()
	var failed: int = (
		_report
		. filter(func(r: Dictionary) -> bool: return not r["result"] in ["ok", SKIPPED])
		. size()
	)
	var summary: Dictionary = {
		"recipe_seed": _recipe_seed,
		"ticks": _ticks,
		"every": _every,
		"horizon": _horizon,
		"error": a_error,
		"failed": failed,
		"checkpoints": _report,
		"wall_seconds": (Time.get_ticks_msec() - _started_msec) / 1000.0,
	}
	var file: FileAccess = FileAccess.open(_out.path_join("report.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(summary, "  "))
		file.close()
	print(
		(
			"save_load_probe: %d checkpoints, %d failed%s"
			% [_report.size(), failed, " — " + a_error if a_error else ""]
		)
	)
	get_tree().quit(0 if a_error.is_empty() and failed == 0 else 1)
