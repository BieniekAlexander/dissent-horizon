extends Node

## ONE MACHINE'S HALF OF A CROSS-PLATFORM DETERMINISM CHECK: a skirmish built from a fixed
## recipe exactly as the lobby builds one — SkirmishLauncher's generator and builder — with every
## slot a bot, run headless to `--ticks`, writing what it computed so two machines' runs can be
## diffed. No network: whether two platforms compute the same match is the question netplay's
## platform refusal waits on (gdd/systems/commands/netplay.md §Decisions, platforms).
##
## Run, on each machine, from the same commit:
##   godot --headless --path . --fixed-fps 30 tools/netplay/determinism_probe.tscn -- \
##       --out=/abs/dir [--ticks=9000] [--seed=20261014] [--dense-from=<tick>]
## then compare the two directories with tools/netplay/compare_determinism.py.
##
## Writes into `--out`:
##   summary.json — platform, engine, build version, recipe, map digest, ticks reached, error;
##   digests.txt  — "<tick> <SimulationDigest>" every tick;
##   states.txt   — "<tick>\t<SimulationDigest.state_string>" every STATE_INTERVAL_TICKS;
##   raw.txt      — "<tick> <serial>:<hex of exact position and velocity floats> …" on the same
##                  ticks: the digest rounds positions, so a drift below its rounding shows here
##                  first.

## Fixes the recipe (factions, map seed, gameplay seed), so both machines play one match.
const DEFAULT_RECIPE_SEED: int = 20261014
## Five simulated minutes: long enough for both bots to build, expand and fight.
const DEFAULT_TICKS: int = 9000
const STATE_INTERVAL_TICKS: int = 30
const PLAYERS: int = 2
## A run that stops advancing (a hung navmesh, an infinite await) gives up rather than hangs.
const GIVE_UP_SECONDS: float = 1800.0

var _out: String = ""
var _ticks: int = DEFAULT_TICKS
var _recipe_seed: int = DEFAULT_RECIPE_SEED
## From this tick on, states.txt and raw.txt take every tick, to name a one-tick difference.
var _dense_from: int = -1
var _scenario: Scenario = null
var _summary: Dictionary = {}
var _digests: FileAccess = null
var _states: FileAccess = null
var _raw: FileAccess = null
var _last_tick: int = -1
var _started_msec: int = 0
var _is_done: bool = false


func _ready() -> void:
	# Sample after every piece has ticked, so a sample is the state the tick left behind.
	process_physics_priority = 1000
	for argument: String in OS.get_cmdline_user_args():
		var pair: PackedStringArray = argument.trim_prefix("--").split("=", true, 1)
		if pair.size() == 2:
			match pair[0]:
				"out":
					_out = pair[1]
				"ticks":
					_ticks = int(pair[1])
				"seed":
					_recipe_seed = int(pair[1])
				"dense-from":
					_dense_from = int(pair[1])
	if _out == "":
		push_error("determinism_probe: no --out directory given.")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(_out)
	_started_msec = Time.get_ticks_msec()
	_summary = {
		"platform": "%s/%s" % [OS.get_name(), Engine.get_architecture_name()],
		"engine": Engine.get_version_info().get("string", ""),
		"build": ReplayFile.current_version(),
		"recipe_seed": _recipe_seed,
		"ticks_asked": _ticks,
		"error": "",
	}
	var setup := SkirmishSetup.new(PLAYERS)
	setup.human_plays_first_slot = false
	setup.set_team(0, 1)
	setup.set_team(1, 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = _recipe_seed
	var recipe: Dictionary = setup.recipe(rng)
	_summary["recipe"] = recipe
	var built: Dictionary = SkirmishLauncher.launch(recipe)
	if built.has("refusal"):
		_finish("launch: %s" % built["refusal"])
		return
	_scenario = built["scenario"]
	_summary["map_seed_played"] = _scenario.skirmish_recipe.get("map_seed", -1)
	_digests = FileAccess.open(_out.path_join("digests.txt"), FileAccess.WRITE)
	_states = FileAccess.open(_out.path_join("states.txt"), FileAccess.WRITE)
	_raw = FileAccess.open(_out.path_join("raw.txt"), FileAccess.WRITE)
	get_tree().root.add_child.call_deferred(_scenario)


func _physics_process(_a_delta: float) -> void:
	if _is_done or _scenario == null or not _scenario.is_inside_tree():
		return
	if Time.get_ticks_msec() - _started_msec > int(GIVE_UP_SECONDS * 1000.0):
		_finish("gave up at tick %d" % _scenario.tick)
		return
	if not _summary.has("map_digest"):
		_summary["map_digest"] = MapDigest.of(_scenario)
	var tick: int = _scenario.tick
	if tick == _last_tick:
		return
	_last_tick = tick
	_digests.store_line("%d %s" % [tick, SimulationDigest.of(_scenario)])
	if tick % STATE_INTERVAL_TICKS == 0 or (_dense_from >= 0 and tick >= _dense_from):
		_states.store_line("%d\t%s" % [tick, SimulationDigest.state_string(_scenario)])
		_raw.store_line("%d %s" % [tick, _raw_line()])
	if tick >= _ticks:
		_finish("")


## Every piece's exact position and velocity, by spawn serial: the bits, not a rounding of them.
func _raw_line() -> String:
	var lines: PackedStringArray = []
	for node: Node in get_tree().get_nodes_in_group("piece"):
		var entity := node as Entity
		if entity == null or entity.spawn_serial == 0 or not entity.is_inside_tree():
			continue
		var p: Vector3 = entity.global_position
		var v: Vector3 = entity.velocity
		var bits: PackedByteArray = (
			PackedFloat64Array([p.x, p.y, p.z, v.x, v.y, v.z]).to_byte_array()
		)
		lines.append("%d:%s" % [entity.spawn_serial, bits.hex_encode()])
	lines.sort()
	return " ".join(lines)


func _finish(a_error: String) -> void:
	_is_done = true
	_summary["error"] = a_error
	_summary["tick_reached"] = _scenario.tick if _scenario != null else -1
	_summary["wall_seconds"] = (Time.get_ticks_msec() - _started_msec) / 1000.0
	for file: FileAccess in [_digests, _states, _raw]:
		if file != null:
			file.close()
	var summary: FileAccess = FileAccess.open(_out.path_join("summary.json"), FileAccess.WRITE)
	if summary != null:
		summary.store_string(JSON.stringify(_summary, "  "))
		summary.close()
	print("determinism_probe: %s" % JSON.stringify(_summary))
	get_tree().quit(0 if a_error == "" else 1)
