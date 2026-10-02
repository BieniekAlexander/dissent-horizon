extends Node

## Runs `sims/*.sim.yaml` simulation specs and reports what happened.
##
## THIS IS NOT PART OF THE GUT SUITE and must never be made part of it. A spec asks a DESIGN
## question — balance, behaviour — whose answer is allowed to move when a stat moves; the
## suite gates the software's correctness and has to stay trustworthy as a gate. See
## gdd/systems/scenario-scripting/simulation-tests.md §A simulation test asks about DESIGN.
##
## Run as a MAIN SCENE rather than via `--script`, so the project's autoloads (DamageTable, …)
## are registered before the entity scripts compile:
##
##   godot --headless --path . --fixed-fps 30 tools/simulation/run_sims.tscn
##   godot --headless --path . --fixed-fps 30 tools/simulation/run_sims.tscn -- \
##       spec=duel_builder_mirror trials=10 seed=1 out=/tmp/sims.json
##
## `--fixed-fps 30` detaches the main loop from wall time, so a 10-second spec takes about a
## second rather than ten. It is not optional for a batch.
##
## Arguments (all optional, `key=value` after `--`):
##   spec=<id|id,id>  only these spec ids (file name without `.sim.yaml`); default: all
##   trials=<n>       runs per spec (default 1). REPETITION LIVES HERE, never in a spec.
##   seed=<n>         seed for trial 0; trial k uses seed+k. Default: the spec's own seed,
##                    else a random one — recorded either way so any trial is re-runnable.
##   out=<path>       write the full result as JSON
##   trace=<path>     write every piece's position and HP on every physics frame — what proves
##                    a refactor left motion unchanged, where pass/fail is far too coarse
##   dir=<res path>   read specs from here instead of res://sims
##   hold=<seconds>   keep the window up this long after the last spec, for WATCHING a run
##
## To watch one play out, drop `--headless` AND `--fixed-fps` (which is what detaches the run
## from wall time) and narrow to one spec:
##
##   godot --path . tools/simulation/run_sims.tscn -- spec=duel_builder_mirror hold=5
##
## Every slot in a spec is a bot, so `Scenario` gives the watcher its spectator camera, HUD and
## fog toggles for free — there is no human rig to make current.
##
## The exit code is 1 when any spec failed to PARSE or BUILD, and 0 otherwise — including
## when expectations were not met. A design claim coming out false is a finding, not a broken
## tool, and a runner that exited non-zero for it would end up wired into a gate.

const SIMS_DIR: String = "res://sims"
const SPEC_SUFFIX: String = ".sim.yaml"

## Physics frames to allow beyond the arena's own backstop before abandoning a trial. Guards
## a run whose scenario never finishes at all (a hung await, a navmesh that never syncs).
const TRIAL_SLACK_FRAMES: int = 600

var _arguments: Dictionary = {}
var _report: Array = []
var _broken: int = 0
## Open while `trace=` is given; see _trace_frame.
var _trace: FileAccess = null


func _ready() -> void:
	_arguments = _parse_arguments()
	var specs: Array = _load_specs()
	if specs.is_empty():
		print("[run_sims] no specs found in %s" % SIMS_DIR)
		get_tree().quit(1)
		return
	var trials: int = int(_arguments.get("trials", "1"))
	if _arguments.has("trace"):
		_trace = FileAccess.open(str(_arguments["trace"]), FileAccess.WRITE)
	for spec: SimSpec in specs:
		await _run_spec(spec, trials)
	_print_summary()
	_write_output()
	if _trace != null:
		_trace.close()
	# A watched run would otherwise vanish the instant its last window elapsed.
	var hold: float = float(_arguments.get("hold", "0"))
	if hold > 0.0:
		print("\n[run_sims] holding for %.0fs — close the window to quit sooner" % hold)
		await get_tree().create_timer(hold).timeout
	get_tree().quit(1 if _broken > 0 else 0)


#region Arguments and discovery
func _parse_arguments() -> Dictionary:
	var parsed: Dictionary = {}
	for argument: String in OS.get_cmdline_user_args():
		var split: int = argument.find("=")
		if split > 0:
			parsed[argument.substr(0, split)] = argument.substr(split + 1)
	return parsed


## Every spec the run covers, parsed. A spec that fails to parse is RETURNED, not dropped:
## reporting it as a failure is the whole point (CLAUDE.md §A skipped test file is invisible).
func _load_specs() -> Array:
	var wanted: Array = []
	if _arguments.has("spec"):
		wanted = str(_arguments["spec"]).split(",")
	var specs: Array = []
	var sims_dir: String = str(_arguments.get("dir", SIMS_DIR))
	var directory: DirAccess = DirAccess.open(sims_dir)
	if directory == null:
		push_error("[run_sims] cannot open %s" % sims_dir)
		return specs
	var files: PackedStringArray = directory.get_files()
	files.sort()
	for file: String in files:
		if not file.ends_with(SPEC_SUFFIX):
			continue
		var id: String = file.replace(SPEC_SUFFIX, "")
		if not wanted.is_empty() and not wanted.has(id):
			continue
		specs.append(SimSpec.parse_file("%s/%s" % [sims_dir, file]))
	return specs


#endregion


#region Running
func _run_spec(a_spec: SimSpec, a_trials: int) -> void:
	print("\n=== %s ===" % a_spec.id)
	if not a_spec.is_valid():
		_broken += 1
		for error: String in a_spec.errors:
			print("  SPEC ERROR: %s" % error)
		_report.append({"spec": a_spec.id, "ok": false, "errors": a_spec.errors})
		return
	if a_spec.description != "":
		print("  %s" % a_spec.description.strip_edges().split("\n")[0])

	var trials: Array = []
	for index: int in a_trials:
		var result: Dictionary = await _run_trial(a_spec, _seed_for(a_spec, index))
		trials.append(result)
		if result.has("build_errors"):
			_broken += 1
			break
	_report.append(
		{
			"spec": a_spec.id,
			"ok": true,
			"trials": trials,
			"passed":
			trials.reduce(
				func(total: int, t: Dictionary) -> int:
					return total + (1 if t.get("passed", false) else 0),
				0
			),
		}
	)


## Seed for trial `a_index`: the CLI's base, else the spec's authored seed, else a fresh
## random one. Trial k is base + k so a batch spreads over seeds rather than repeating one.
##
## Whatever is chosen is RECORDED in the result, which is what keeps a non-deterministic
## simulation usable: a 7-of-10 result can be reopened at the seed that lost.
func _seed_for(a_spec: SimSpec, a_index: int) -> int:
	if _arguments.has("seed"):
		return int(_arguments["seed"]) + a_index
	if a_spec.seed_value >= 0:
		return a_spec.seed_value + a_index
	return randi() + a_index


func _run_trial(a_spec: SimSpec, a_seed: int) -> Dictionary:
	var arena: SimArena = SimArena.build(a_spec, a_seed)
	if not arena.build_errors.is_empty():
		for error: String in arena.build_errors:
			print("  BUILD ERROR: %s" % error)
		arena.free()
		return {"seed": a_seed, "build_errors": a_spec.errors + arena.build_errors}

	add_child(arena)
	var cap: int = arena.max_ticks + TRIAL_SLACK_FRAMES
	var frames: int = 0
	while not arena.is_finished() and frames < cap:
		await get_tree().physics_frame
		frames += 1
		_trace_frame(a_spec, a_seed, arena, frames)

	var result: Dictionary = {
		"seed": a_seed,
		"passed": arena.is_finished() and arena.all_passed(),
		"settled": arena.is_finished(),
		"checks": arena.check_results() if arena.is_finished() else [],
	}
	if not arena.is_finished():
		print("  TRIAL seed %d: did not settle within %d frames" % [a_seed, cap])
	arena.queue_free()
	await get_tree().process_frame
	return result


#endregion


## One line per piece in the arena: where it is and how hurt, rounded so float noise far below
## anything visible does not read as a difference.
func _trace_frame(a_spec: SimSpec, a_seed: int, a_arena: Node, a_frame: int) -> void:
	if _trace == null:
		return
	for node: Node in get_tree().get_nodes_in_group("piece"):
		var piece: Entity = node as Entity
		if piece == null or not a_arena.is_ancestor_of(piece):
			continue
		var at: Vector3 = piece.global_position
		var hp: float = piece.defense.hp if piece.defense != null else 0.0
		_trace.store_line(
			(
				"%s %d %d %s %.3f %.3f %.3f %.1f"
				% [a_spec.id, a_seed, a_frame, piece.name, at.x, at.y, at.z, hp]
			)
		)


#endregion


#region Reporting
func _print_summary() -> void:
	print("\n=== summary ===")
	for entry: Dictionary in _report:
		if not entry.get("ok", false):
			print("  %-34s SPEC ERROR (%d)" % [entry["spec"], (entry["errors"] as Array).size()])
			continue
		var trials: Array = entry["trials"]
		var passed: int = entry["passed"]
		var seeds: Array = []
		for trial: Dictionary in trials:
			if not trial.get("passed", false):
				seeds.append(trial["seed"])
		var failing: String = "" if seeds.is_empty() else "  failing seeds: %s" % str(seeds)
		print("  %-34s %d/%d met%s" % [entry["spec"], passed, trials.size(), failing])
	if _broken > 0:
		print("\n%d spec(s) could not be parsed or built — a BROKEN SPEC, not a finding." % _broken)


func _write_output() -> void:
	if not _arguments.has("out"):
		return
	var path: String = str(_arguments["out"])
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("[run_sims] cannot write %s" % path)
		return
	file.store_string(JSON.stringify(_report, "\t"))
	file.close()
	print("\n[run_sims] wrote %s" % path)
#endregion
