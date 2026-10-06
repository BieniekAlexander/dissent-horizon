extends Node

## TEMPORARY profiling harness (safe to delete). Boots a scenario scene with every
## player slot forced to a bot (spectator session), then samples per-physics-tick cost.
##
## Usage:
##   godot --headless --path <proj> res://tools/_perf_probe_tmp.tscn -- \
##       --out=/abs/path.csv --ticks=36000 [--scene=res://...] [--mode=match|sweep]
##       [--sweep-step=20] [--sweep-period=450] [--sweep-max=400] [--brains=1]
##
## Emits one CSV row per tick. Timing method:
##   * a hook node at physics priority -10000 stamps t0 (start of the script phase)
##   * a hook at +10000 stamps t1 -> script_us = all _physics_process work this tick
##   * fog and bot-brain nodes are taken OVER (their own _physics_process disabled and
##     driven from hooks at the same relative priority) so their share is timed directly.


class Hook:
	extends Node
	var cb: Callable
	var prio: int = 0

	func _init(a_prio: int, a_cb: Callable) -> void:
		prio = a_prio
		cb = a_cb

	func _ready() -> void:
		process_physics_priority = prio

	func _physics_process(a_delta: float) -> void:
		cb.call(a_delta)


## BotBrain's job names (BotBrain._build_jobs); a job's microseconds are summed across bots.
const STAGES: Array[String] = [
	"momentum",
	"targeting",
	"military",
	"sanction",
	"kamikaze",
	"preservation",
	"opportunist",
	"economy",
	"production",
	"scout_sight",
	"scout",
]

var out_path: String = "res://tools/_perf_probe_out.csv"
var tick_limit: int = 3600
var scene_path: String = "res://scenes/scenarios/skirmish.tscn"
var mode: String = "match"
var brains_enabled: bool = true
var sweep_step: int = 20
var sweep_period: int = 450
var sweep_max: int = 400
var time_scale: float = 1.0

var scenario: Node = null
var _brains: Array = []
var _fogs: Array = []
var _map: Node = null
var _nav: Node = null

var _tick: int = 0
var _t0: int = 0
var _script_us: int = 0
var _fog_us: int = 0
var _brain_us: int = 0
var _stage_us: Dictionary = {}
var _think_this_tick: int = 0
var _rows: PackedStringArray = PackedStringArray()
var _f: FileAccess = null
var _wall_start: int = 0
var _last_wall: int = 0
var _cells_changed: int = 0
var _sweep_spawned: int = 0
var _bound: bool = false
var _unit_scenes: Array = []


func _ready() -> void:
	_parse_args()
	Engine.set_meta(&"fprof", {})
	_f = FileAccess.open(out_path, FileAccess.WRITE)
	if _f == null:
		push_error("perf probe: cannot open %s" % out_path)
		get_tree().quit(1)
		return
	var header: PackedStringArray = PackedStringArray(
		[
			"tick",
			"wall_us",
			"sample_us",
			"script_us",
			"fog_us",
			"brain_us",
			"think",
			"phys_ms",
			"proc_ms",
			"nav_ms",
			"commandables",
			"units",
			"structures",
			"projectiles",
			"los",
			"nodes",
			"orphans",
			"objects",
			"mem_mb",
			"phys_active",
			"phys_pairs",
			"phys_islands",
			"nav_agents",
			"nav_polys",
			"cells_changed",
			"e1",
			"e2",
		]
	)
	for s: String in STAGES:
		header.append("s_" + s)
	header.append("keys_us")
	_f.store_line(",".join(header))

	var packed: PackedScene = load(scene_path)
	scenario = packed.instantiate()
	_force_all_bots(scenario)
	add_child(scenario)

	add_child(Hook.new(-10000, _hook_start))
	add_child(Hook.new(1, _hook_fog))
	add_child(Hook.new(90, _hook_brains))
	add_child(Hook.new(10000, _hook_end))
	_wall_start = Time.get_ticks_usec()
	_last_wall = _wall_start
	Engine.time_scale = time_scale


func _parse_args() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var parts: PackedStringArray = arg.split("=", true, 1)
		var key: String = parts[0].trim_prefix("--")
		var val: String = parts[1] if parts.size() > 1 else ""
		match key:
			"out":
				out_path = val
			"ticks":
				tick_limit = val.to_int()
			"scene":
				scene_path = val
			"mode":
				mode = val
			"brains":
				brains_enabled = val.to_int() != 0
			"sweep-step":
				sweep_step = val.to_int()
			"sweep-period":
				sweep_period = val.to_int()
			"sweep-max":
				sweep_max = val.to_int()
			"time-scale":
				time_scale = val.to_float()
			"fprof-keys":
				fprof_keys = PackedStringArray(val.split(","))


## Every slot becomes a bot so the session is a spectator match that needs no input.
func _force_all_bots(a_scenario: Node) -> void:
	var slots: Array = a_scenario.get("player_slots")
	var out: Array[PlayerSlot] = []
	for slot: PlayerSlot in slots:
		var copy: PlayerSlot = slot.duplicate() as PlayerSlot
		copy.is_bot = true
		copy.difficulty = PlayerSlot.Difficulty.MEDIUM
		out.append(copy)
	a_scenario.set("player_slots", out)


func _bind() -> void:
	if _bound:
		return
	_map = scenario.get("map")
	if _map == null:
		return
	_nav = _map.get("nav_manager")
	for c: Node in scenario.get("commanders"):
		for child: Node in c.get_children():
			if child is BotBrain:
				_brains.append(child)
				if not brains_enabled:
					child.set("active", false)
	for f: Node in scenario.find_children("", "Fog", true, false):
		_fogs.append(f)
		f.set_physics_process(false)
	var grid: Object = _map.get("terrain_grid")
	if grid != null and grid.has_signal("cells_changed"):
		grid.connect("cells_changed", func(_a = null) -> void: _cells_changed += 1)
	_bound = true


# ─── HOOKS ──────────────────────────────────────────────────────────────────


func _hook_start(_a_delta: float) -> void:
	_bind()
	if Engine.has_meta(&"fprof"):
		_fprof_at_start = (Engine.get_meta(&"fprof") as Dictionary).duplicate()
	_fog_us = 0
	_brain_us = 0
	_think_this_tick = 0
	_stage_us.clear()
	_t0 = Time.get_ticks_usec()


func _hook_fog(a_delta: float) -> void:
	var t: int = Time.get_ticks_usec()
	for f: Node in _fogs:
		if is_instance_valid(f):
			f._physics_process(a_delta)
	_fog_us = Time.get_ticks_usec() - t


## Read what the scheduler's jobs cost this tick. The scheduler runs at its own priority, before
## this hook (priority 90) only if its priority is lower; it is 0, so by now it has run.
func _hook_brains(_a_delta: float) -> void:
	var scheduler: BotScheduler = (
		get_tree().get_first_node_in_group(BotScheduler.GROUP) as BotScheduler
	)
	if scheduler == null:
		return
	for entry: Dictionary in scheduler.report():
		if not entry["ran_this_tick"]:
			continue
		_brain_us += int(entry["usec"])
		var name: String = String(entry["name"])
		_stage_us[name] = int(_stage_us.get(name, 0)) + int(entry["usec"])
		_think_this_tick += 1
		# Calibration totals: microseconds against reported work units, per job.
		var totals: Array = _job_totals.get(name, [0, 0, 0])
		_job_totals[name] = [
			totals[0] + int(entry["usec"]), totals[1] + int(entry["units"]), totals[2] + 1
		]


## Timed functions (wrap.py keys, e.g. "movement.is_navigation_finished") whose time this tick
## is summed into the CSV's last column, `keys_us`.
var fprof_keys: PackedStringArray = PackedStringArray()
var _keys_us: int = 0

## A tick whose script phase runs longer than this also gets its own per-function breakdown.
const FPROF_SPIKE_US: int = 20000
## The per-function timings as they stood when this tick began, to take one tick's share.
var _fprof_at_start: Dictionary = {}

## Ticks per window of the per-function timings, when functions are wrapped in timers (the
## scratch wrap.py writes into Engine meta "fprof"). One simulated minute.
const FPROF_WINDOW_TICKS: int = 1800


func _hook_end(_a_delta: float) -> void:
	_script_us = Time.get_ticks_usec() - _t0
	_keys_us = 0
	if not fprof_keys.is_empty() and Engine.has_meta(&"fprof"):
		var timings_now: Dictionary = Engine.get_meta(&"fprof")
		for key: String in fprof_keys:
			_keys_us += maxi(0, int(timings_now.get(key, 0)) - int(_fprof_at_start.get(key, 0)))
	if _script_us > FPROF_SPIKE_US and Engine.has_meta(&"fprof"):
		var now_timings: Dictionary = Engine.get_meta(&"fprof")
		var spike: Dictionary = {}
		for key: String in now_timings:
			var d: int = int(now_timings[key]) - int(_fprof_at_start.get(key, 0))
			if d > 0:
				spike[key] = d
		if not spike.is_empty():
			var spikes := FileAccess.open(
				out_path + ".spikes.jsonl",
				(
					FileAccess.READ_WRITE
					if FileAccess.file_exists(out_path + ".spikes.jsonl")
					else FileAccess.WRITE
				)
			)
			spikes.seek_end()
			spikes.store_line(
				JSON.stringify({"tick": _tick + 1, "script_us": _script_us, "timings": spike})
			)
			spikes.close()
	if _tick > 0 and _tick % FPROF_WINDOW_TICKS == 0 and Engine.has_meta(&"fprof"):
		var timings: Dictionary = Engine.get_meta(&"fprof")
		if not timings.is_empty():
			var dump := FileAccess.open(
				out_path + ".fprof.jsonl",
				(
					FileAccess.READ_WRITE
					if FileAccess.file_exists(out_path + ".fprof.jsonl")
					else FileAccess.WRITE
				)
			)
			dump.seek_end()
			dump.store_line(JSON.stringify({"tick": _tick, "timings": timings}))
			dump.close()
			timings.clear()
	var now: int = Time.get_ticks_usec()
	var wall: int = now - _last_wall
	_last_wall = now
	_tick += 1
	if mode == "sweep":
		_sweep(_tick)
	_write_row(wall)
	if _tick >= tick_limit:
		_finish()


# ─── SAMPLING ───────────────────────────────────────────────────────────────

## job name -> [total usec, total work units, runs]
var _job_totals: Dictionary = {}
var _sample_us: int = 0
var _proj_cache: int = 0


func _write_row(a_wall: int) -> void:
	var sample_t0: int = Time.get_ticks_usec()
	var tree: SceneTree = get_tree()
	var commandables: int = tree.get_nodes_in_group("piece").size()
	var units: int = tree.get_nodes_in_group("unit").size()
	var structures: int = tree.get_nodes_in_group("structure").size()
	var los: int = tree.get_nodes_in_group("los").size()
	if _tick % 30 == 0:
		_proj_cache = _count_projectiles()
	var projectiles: int = _proj_cache
	var e1: int = 0
	var e2: int = 0
	if _bound and scenario != null:
		var cs: Array = scenario.get("commanders")
		if cs.size() > 1 and is_instance_valid(cs[1]):
			e1 = cs[1].get_children().size()
		if cs.size() > 2 and is_instance_valid(cs[2]):
			e2 = cs[2].get_children().size()
	var row: PackedStringArray = PackedStringArray(
		[
			str(_tick),
			str(a_wall),
			str(_sample_us),
			str(_script_us),
			str(_fog_us),
			str(_brain_us),
			str(_think_this_tick),
			"%.4f" % (Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0),
			"%.4f" % (Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0),
			"%.4f" % (Performance.get_monitor(Performance.TIME_NAVIGATION_PROCESS) * 1000.0),
			str(commandables),
			str(units),
			str(structures),
			str(projectiles),
			str(los),
			str(int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))),
			str(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))),
			str(int(Performance.get_monitor(Performance.OBJECT_COUNT))),
			"%.2f" % (Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0),
			str(int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS))),
			str(int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS))),
			str(int(Performance.get_monitor(Performance.PHYSICS_3D_ISLAND_COUNT))),
			str(int(Performance.get_monitor(Performance.NAVIGATION_3D_AGENT_COUNT))),
			str(int(Performance.get_monitor(Performance.NAVIGATION_3D_POLYGON_COUNT))),
			str(_cells_changed),
			str(e1),
			str(e2),
		]
	)
	for s: String in STAGES:
		row.append(str(int(_stage_us.get(s, 0))))
	row.append(str(_keys_us))
	_f.store_line(",".join(row))
	_sample_us = Time.get_ticks_usec() - sample_t0
	if _tick % 300 == 0:
		_f.flush()
		print(
			(
				"[probe] tick=%d cmd=%d script_us=%d brain_us=%d nodes=%d"
				% [
					_tick,
					commandables,
					_script_us,
					_brain_us,
					int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
				]
			)
		)


func _count_projectiles() -> int:
	var n: int = 0
	for node: Node in scenario.find_children("Locomotion", "PhasedLocomotion", true, false):
		n += 1
	return n


# ─── SWEEP MODE ─────────────────────────────────────────────────────────────


## Spawn `sweep_step` more units per commander every `sweep_period` ticks, so the tick
## cost can be read against a known population instead of whatever the match happens
## to field.
func _sweep(a_tick: int) -> void:
	if a_tick < 600 or a_tick % sweep_period != 0:
		return
	if _sweep_spawned >= sweep_max:
		return
	if _map == null:
		return
	if _unit_scenes.is_empty():
		_collect_unit_scenes()
	if _unit_scenes.is_empty():
		return
	var cs: Array = scenario.get("commanders")
	for ci: int in range(1, cs.size()):
		var commander: Node = cs[ci]
		var origin: Vector2 = _commander_origin(commander)
		var batch: Array = []
		for i: int in sweep_step:
			batch.append((_unit_scenes[i % _unit_scenes.size()] as PackedScene).instantiate())
		_map.call("add_entities", batch, origin, commander)
	_sweep_spawned += sweep_step
	print("[probe] sweep -> +%d per commander (total %d each)" % [sweep_step, _sweep_spawned])


func _collect_unit_scenes() -> void:
	for p: String in [
		"res://scenes/entities/units/cl/cl_bioLight_antiLight.tscn",
		"res://scenes/entities/units/cl/cl_bioMedium_antiStrong.tscn",
	]:
		if ResourceLoader.exists(p):
			_unit_scenes.append(load(p))


func _commander_origin(a_commander: Node) -> Vector2:
	for child: Node in a_commander.get_children():
		if child is Node3D and child.is_in_group("structure"):
			return VU.in_xz((child as Node3D).global_position)
	for child: Node in a_commander.get_children():
		if child is Node3D and child.is_in_group("unit"):
			return VU.in_xz((child as Node3D).global_position)
	return Vector2.ZERO


# ─── SHUTDOWN ───────────────────────────────────────────────────────────────


func _finish() -> void:
	# One-off measurement of a navmesh rebuild, which is deferred and so never lands
	# inside the sampled window.
	var rebuild_us: Array[int] = []
	if _nav != null and _nav.has_method("_rebuild_navmesh"):
		for i: int in 3:
			var t: int = Time.get_ticks_usec()
			_nav.set("_built_once", false)  # force a whole-map rebuild rather than a no-op
			_nav.call("_rebuild_navmesh")
			rebuild_us.append(Time.get_ticks_usec() - t)
	var total_s: float = (Time.get_ticks_usec() - _wall_start) / 1000000.0
	_f.store_line("# rebuild_us=%s total_wall_s=%.2f ticks=%d" % [str(rebuild_us), total_s, _tick])
	for name: String in _job_totals:
		var t: Array = _job_totals[name]
		_f.store_line(
			(
				"# job %s runs=%d usec=%d units=%d usec_per_unit=%.3f"
				% [name, t[2], t[0], t[1], float(t[0]) / maxf(1.0, float(t[1]))]
			)
		)
	_f.flush()
	_f.close()
	print("[probe] DONE ticks=%d wall=%.1fs rebuild_us=%s" % [_tick, total_s, str(rebuild_us)])
	get_tree().quit(0)
