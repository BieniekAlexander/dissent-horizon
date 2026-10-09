extends GutTest

## THE SIMULATION IS REPRODUCIBLE FROM ONE NUMBER, and these are the tests of that claim.
##
## A run that cannot be repeated cannot be measured: a duel ("which of these two units
## wins?") has to be reported as a distribution over N trials rather than answered once, and
## a regression cannot be pinned at all because the run that failed cannot be replayed. That
## is what `Scenario.rng_seed` and `Scenario.seed_simulation()` exist for, and what the
## self-play harness (tools/selfplay/) is built on top of.
##
## Three things are asserted, in the order they matter:
##   1. Every gameplay draw goes through a generator the scenario seeds.
##   2. Seeding twice with the same number reproduces the sequence, and a different number
##      produces a different one.
##   3. No script has re-introduced an unseeded global draw (the SOURCE SCAN below) — the
##      guard, because the failure mode is silent: an unseeded draw does not error, it just
##      makes every measurement taken afterwards mean nothing.

## Names that draw from Godot's GLOBAL generator when called bare. `SU.rng.randf()` is fine
## (it is prefixed); `randf()` is not.
const _GLOBAL_DRAW_NAMES: Array[String] = [
	"randf",
	"randf_range",
	"randi",
	"randi_range",
	"randomize",
]

## Scripts permitted to call a global draw anyway, each with the reason. EMPTY, deliberately:
## every gameplay site was routed through `SU.rng` and every generator that wants its own
## stream (the terrain generators) already owns a seeded `RandomNumberGenerator`. A new entry
## here is a decision to make part of the simulation unreplayable, so it should be argued for
## in the comment rather than added to make a red test green.
const _ACKNOWLEDGED_GLOBAL_DRAWS: Array[String] = []

## Calls that read the WALL CLOCK. Simulation code reading one would play differently on a
## replay of the same seed (gdd/systems/commands/recording-and-replay.md §Detecting drift).
## Conversions that take a time as an argument (`get_datetime_dict_from_unix_time`) are not
## reads, and are not listed.
const _WALL_CLOCK_READS: Array[String] = [
	"Time.get_ticks_msec",
	"Time.get_ticks_usec",
	"Time.get_unix_time_from_system",
	"Time.get_datetime_dict_from_system",
	"Time.get_datetime_string_from_system",
	"Time.get_date_dict_from_system",
	"Time.get_time_dict_from_system",
	"OS.get_ticks_msec",
]

## Scripts allowed to read the wall clock, each for a reason that never reaches the simulation.
const _ACKNOWLEDGED_WALL_CLOCK_READS: Dictionary = {
	"res://scripts/entities/components/selectable.gd": "double-click timing",
	"res://scripts/interface/rts_controller.gd": "double-click timing",
	"res://scripts/interface/hud/resource_pressure.gd": "a pulsing HUD bar",
	"res://scripts/interface/scenario_highlight.gd": "a pulsing highlight",
	"res://scripts/interface/commander/bot_scheduler.gd": "diagnostic job timing, never read back",
	"res://scripts/replay/replay_recorder.gd": "names an autosave file",
	"res://scripts/replay/replay_save_form.gd": "prefills a kept replay's name",
}


#region The seed reproduces a run
func test_the_same_seed_reproduces_the_gameplay_stream() -> void:
	assert_eq(_gameplay_draws(4242), _gameplay_draws(4242), "same seed, same gameplay draws")


func test_a_different_seed_produces_a_different_stream() -> void:
	assert_ne(_gameplay_draws(4242), _gameplay_draws(4243), "a different seed is a different match")


## The other half of the pair, and the one that is easy to forget: an authored scenario
## expression ("15 + randi_range(0, 10)") is evaluated by Godot's `Expression`, which resolves
## the @GlobalScope built-ins itself and cannot be pointed at SU.rng. seed_simulation() seeds
## that generator too, which is the only thing that makes a wave's interval replayable.
func test_the_same_seed_reproduces_an_authored_expression() -> void:
	assert_eq(_expression_draws(99), _expression_draws(99), "same seed, same wave intervals")
	assert_ne(
		_expression_draws(99),
		_expression_draws(100),
		"a different seed rolls different wave intervals"
	)


## Hitscan spread was the ORIGINAL offender: it called the global `randf_range`, so the same
## scenario diverged from the first shot fired.
func test_hitscan_spread_is_reproducible() -> void:
	var payload: Payload = autofree(Payload.new())
	var straight := Vector3(1.0, 0.0, 0.0)

	var first: Array[Vector3] = []
	SU.rng.seed = 7
	for _i: int in 5:
		first.append(payload.aim_error(straight))

	var second: Array[Vector3] = []
	SU.rng.seed = 7
	for _i: int in 5:
		second.append(payload.aim_error(straight))

	assert_eq(first, second, "the same seed puts the same spread on the same shot")
	assert_ne(first[0], straight, "there is still a spread to reproduce")


## A barrage's muzzle scatter, the third site — named by neither the task's audit nor the
## TODO it left behind, and found by re-running the grep.
func test_a_barrage_scatters_its_muzzles_reproducibly() -> void:
	SU.rng.seed = 11
	var first: Vector2 = EventMortarBarrage._launch_offset()
	SU.rng.seed = 11
	assert_eq(
		EventMortarBarrage._launch_offset(),
		first,
		"the same seed lands the shells on the same arcs"
	)


#endregion


#region Scenario owns the seed
func test_a_scenario_seeds_the_gameplay_generator_at_boot() -> void:
	SU.rng.seed = 0
	var scenario: Scenario = autofree(Scenario.new())
	scenario.rng_seed = 31337
	scenario.seed_simulation()
	assert_eq(SU.rng.seed, 31337, "the scenario's seed IS the gameplay generator's seed")


## The two generators must not run in lockstep off one number — hence the salt. Compared as
## the values each produces rather than as seeds, because a seed is only interesting through
## the stream it makes.
func test_the_two_streams_are_not_the_same_stream() -> void:
	var scenario: Scenario = autofree(Scenario.new())
	scenario.rng_seed = 5
	scenario.seed_simulation()
	var gameplay: Array[int] = []
	for _i: int in 8:
		gameplay.append(SU.rng.randi_range(0, 1_000_000))
	scenario.seed_simulation()
	var global_stream: Array[int] = []
	for _i: int in 8:
		global_stream.append(randi_range(0, 1_000_000))
	assert_ne(gameplay, global_stream, "salted, so the two generators are not one generator")


#endregion


#region The guard: no script draws from an unseeded generator
## Asserted over FILE TEXT rather than by running anything, for the same reason
## test_SuiteIntegrity is: the failure this catches is a line somebody wrote, and a test that
## had to EXECUTE that line to notice would only fail on the runs that happened to reach it.
func test_no_script_draws_from_the_global_generator() -> void:
	var offenders: Array[String] = []
	for path: String in _gd_scripts_under("res://scripts"):
		if _ACKNOWLEDGED_GLOBAL_DRAWS.has(path):
			continue
		for line_number: int in _global_draw_lines(path):
			offenders.append("%s:%d" % [path, line_number])
	assert_eq(
		offenders,
		[] as Array[String],
		"unseeded global RNG draw(s) — route through SU.rng, or acknowledge with a reason"
	)


## The same guard for the wall clock: a simulation decision that reads it plays differently on
## every run, so a replay of the same seed would drift.
func test_no_simulation_script_reads_the_wall_clock() -> void:
	var offenders: Array[String] = []
	for path: String in _gd_scripts_under("res://scripts"):
		if _ACKNOWLEDGED_WALL_CLOCK_READS.has(path):
			continue
		var file: FileAccess = FileAccess.open(path, FileAccess.READ)
		var lines: PackedStringArray = file.get_as_text().split("\n")
		file.close()
		for i: int in lines.size():
			var code: String = _strip_strings_and_comments(lines[i])
			for read: String in _WALL_CLOCK_READS:
				if code.contains(read + "("):
					offenders.append("%s:%d" % [path, i + 1])
	assert_eq(
		offenders,
		[] as Array[String],
		"wall-clock read(s) in simulation code — use the scenario tick, or acknowledge a UI use"
	)


#endregion


#region Helpers
## `a_count` draws from the gameplay generator after seeding a scenario with `a_seed`.
func _gameplay_draws(a_seed: int, a_count: int = 8) -> Array[int]:
	var scenario: Scenario = autofree(Scenario.new())
	scenario.rng_seed = a_seed
	scenario.seed_simulation()
	var draws: Array[int] = []
	for _i: int in a_count:
		draws.append(SU.rng.randi_range(0, 1_000_000))
	return draws


## The same, through an authored scenario expression — i.e. through Godot's Expression and
## the global generator behind it.
func _expression_draws(a_seed: int, a_count: int = 8) -> Array[int]:
	var scenario: Scenario = autofree(Scenario.new())
	scenario.rng_seed = a_seed
	scenario.seed_simulation()
	var draws: Array[int] = []
	for _i: int in a_count:
		draws.append(ScenarioExpression.evaluate_int("randi_range(0, 1000000)", -1, null))
	return draws


## Every .gd file under `a_root`, recursively.
func _gd_scripts_under(a_root: String) -> Array[String]:
	var found: Array[String] = []
	for entry: String in DirAccess.get_directories_at(a_root):
		found.append_array(_gd_scripts_under("%s/%s" % [a_root, entry]))
	for entry: String in DirAccess.get_files_at(a_root):
		if entry.ends_with(".gd"):
			found.append("%s/%s" % [a_root, entry])
	return found


## Line numbers in `a_path` that call a global draw. Strings and comments are removed first:
## `@export_placeholder("… randi_range(0, 10) …")` documents an authored expression and is
## not a draw, and neither is a doc comment naming one.
func _global_draw_lines(a_path: String) -> Array[int]:
	var file: FileAccess = FileAccess.open(a_path, FileAccess.READ)
	if file == null:
		return []
	var lines: PackedStringArray = file.get_as_text().split("\n")
	file.close()
	var found: Array[int] = []
	for i: int in lines.size():
		var code: String = _strip_strings_and_comments(lines[i])
		for draw_name: String in _GLOBAL_DRAW_NAMES:
			if _calls_bare(code, draw_name):
				found.append(i + 1)
				break
	return found


## `a_line` with every quoted literal and trailing comment removed.
func _strip_strings_and_comments(a_line: String) -> String:
	var out: String = ""
	var quote: String = ""
	for i: int in a_line.length():
		var ch: String = a_line[i]
		if quote != "":
			if ch == quote:
				quote = ""
			continue
		if ch == '"' or ch == "'":
			quote = ch
			continue
		if ch == "#":
			break
		out += ch
	return out


## Whether `a_code` calls `a_name` UNPREFIXED — `randf()` yes, `SU.rng.randf()` no, and
## `my_randf()` no either.
func _calls_bare(a_code: String, a_name: String) -> bool:
	var from: int = 0
	while true:
		var at: int = a_code.find(a_name + "(", from)
		if at < 0:
			return false
		from = at + 1
		if at > 0 and (a_code[at - 1] == "." or _is_identifier_char(a_code[at - 1])):
			continue
		return true
	return false


func _is_identifier_char(a_ch: String) -> bool:
	return a_ch == "_" or (a_ch.to_lower() != a_ch.to_upper()) or a_ch.is_valid_int()
#endregion
