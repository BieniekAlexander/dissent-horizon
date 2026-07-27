class_name ScenarioExpression
extends RefCounted

## Small numeric expressions authored directly into scenario fields — "2 + fires",
## "15 + randi_range(0, 5)", "tick / 1000.0" — so a wave can vary its interval or grow its
## size without a bespoke export for every knob.
##
## Built on Godot's OWN `Expression` class, which is exactly this problem already solved:
## it parses a GDScript-flavoured expression, takes named inputs, and evaluates without
## running arbitrary statements. No addon needed, and nothing here re-implements a parser.
##
## What an expression may use:
##   * arithmetic and the @GlobalScope built-ins — randi_range, randf, min, max, clamp,
##     pow, floor, round, sin, … (verified available inside Expression)
##   * the named inputs below
##
## What it may NOT use — and this is a hard limit of Expression, not a choice made here:
## ENGINE SINGLETONS are unreachable. `Engine.get_physics_frames()` fails with "Invalid
## named index 'Engine'" whether or not a base instance is passed. Use `tick` instead,
## which is better anyway: it counts SCENARIO physics ticks, so it is scenario-relative
## and stops while a dialog holds the simulation, where the engine's own counter keeps
## running through the pause.
##
## `randi_range` inside an expression draws from Godot's GLOBAL generator, and there is no
## way to redirect it: `Expression` resolves the @GlobalScope built-ins itself, and the
## alternative — passing `SU.rng` in as a base instance — is exactly the thing the paragraph
## below refuses to do. So the global generator is SEEDED instead, by
## `Scenario.seed_simulation()`, from the same authored seed `SU.rng` gets. Two generators,
## one seed: a wave authored as "15 + randi_range(0, 10)" picks the same interval on every
## replay of the same scenario. See gdd/systems/ai/selfplay-harness.md §Determinism.
##
## Deliberately no base instance is passed to execute(): with one, every property and
## method of the host node would become reachable from authored text. Keeping it null means
## an expression can read exactly the inputs below and nothing else.

## The variables every scenario expression can reference. Parse-time fixed, so an expression
## naming anything else fails loudly rather than silently reading zero.
##   tick    — scenario physics ticks elapsed (Scenario.tick)
##   seconds — the same clock in seconds
##   fires   — how many times the owning trigger has fired already; 0 the first time, so
##             "2 + fires" spawns 2, then 3, then 4 …
## Declared as Array[String] rather than PackedStringArray because a PackedStringArray
## constructor call is not a constant expression in GDScript; Expression.parse takes the
## packed form, so _parse converts on the way in.
const INPUT_NAMES: Array[String] = ["tick", "seconds", "fires"]

## Parsed expressions keyed by source text, so re-evaluating a field every cycle doesn't
## re-parse it. A failed parse caches `null`, which also keeps its warning to one per source
## rather than one per evaluation.
static var _parsed: Dictionary = {}


#region Public API
## Whether `source` is worth evaluating at all — an unset expression field falls back to its
## companion numeric export.
static func is_authored(source: String) -> bool:
	return not source.strip_edges().is_empty()


## Evaluate `source` to a float, falling back to `fallback` (with a warning naming `where`)
## on a parse error, a runtime error, or a non-numeric result. Never throws: a mistyped
## expression degrades the scenario to its authored constant instead of breaking the mission.
static func evaluate_float(
	source: String,
	fallback: float,
	manager: ScenarioTriggerManager,
	fires: int = 0,
	where: String = "scenario expression"
) -> float:
	if not is_authored(source):
		return fallback
	var expression: Expression = _parse(source, where)
	if expression == null:
		return fallback

	var result: Variant = expression.execute(_inputs(manager, fires), null, false)
	if expression.has_execute_failed():
		# The usual cause is a name that isn't in INPUT_NAMES — Expression reports it as an
		# "Invalid named index", which is opaque on its own, so list what IS available.
		push_warning("%s: could not evaluate \"%s\" (%s). Available: %s. Using %s."
			% [where, source, expression.get_error_text(), ", ".join(PackedStringArray(INPUT_NAMES)), fallback])
		return fallback
	if not (result is int or result is float):
		push_warning("%s: \"%s\" produced %s, not a number. Using %s."
			% [where, source, type_string(typeof(result)), fallback])
		return fallback
	return float(result)


## Editor-time check: "" when `source` is usable, otherwise a description of what is wrong,
## phrased for an author rather than a programmer.
##
## Exists because the runtime failure mode is a SILENT FALLBACK — a mistyped variable name
## evaluates to the default and the wave just comes out the wrong size, with only a line in
## the output log to say why. Callers surface this through _get_configuration_warnings, which
## puts the problem on the node in the Scene dock while it is being authored.
##
## Runs the expression once with dummy inputs, because an unknown NAME (the likeliest typo)
## is not a parse error — Expression only discovers it at execute time. Deliberately builds
## its own Expression rather than using the shared cache, so editing a field re-checks it.
static func validation_error(source: String) -> String:
	if not is_authored(source):
		return ""
	var expression := Expression.new()
	if expression.parse(source, PackedStringArray(INPUT_NAMES)) != OK:
		return "cannot be parsed (%s)" % expression.get_error_text()
	var result: Variant = expression.execute([0, 0.0, 0], null, false)
	if expression.has_execute_failed():
		return "cannot be evaluated (%s) — the available variables are %s" % [
			expression.get_error_text(), ", ".join(PackedStringArray(INPUT_NAMES))
		]
	if not (result is int or result is float):
		return "produces %s, not a number" % type_string(typeof(result))
	return ""


## Evaluate `source` to an int. Rounds rather than truncates, so "count / 2.0" on an odd
## count lands on the nearer whole number instead of always down.
static func evaluate_int(
	source: String,
	fallback: int,
	manager: ScenarioTriggerManager,
	fires: int = 0,
	where: String = "scenario expression"
) -> int:
	return int(roundf(evaluate_float(source, float(fallback), manager, fires, where)))
#endregion


#region Internals
## Parse `source` once and cache it. Returns null when the text doesn't parse.
static func _parse(source: String, where: String) -> Expression:
	if _parsed.has(source):
		return _parsed[source]
	var expression := Expression.new()
	if expression.parse(source, PackedStringArray(INPUT_NAMES)) != OK:
		push_warning("%s: could not parse \"%s\" (%s). Using the authored value instead."
			% [where, source, expression.get_error_text()])
		_parsed[source] = null
		return null
	_parsed[source] = expression
	return expression


## Values for INPUT_NAMES, in the same order. A null manager/scenario reads as tick 0 rather
## than failing — an expression evaluated off-session (a test, a tool script) should still
## produce a number.
static func _inputs(manager: ScenarioTriggerManager, fires: int) -> Array:
	var tick: int = 0
	if manager != null and manager.scenario != null:
		tick = manager.scenario.tick
	return [tick, TimeUtils.seconds_from_ticks(tick), fires]
#endregion
