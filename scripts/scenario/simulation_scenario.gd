class_name SimulationScenario
extends Scenario

## A Scenario that asks a DESIGN question of the live game end-to-end.
##
## It boots the REAL game (commanders, BotBrains, the full perception → decision → action
## loop), runs it, and folds a set of [SimulationCheck]s into a verdict.
##
## NOT a unit test, and deliberately outside the GUT suite: what it measures is balance and
## behaviour, which is allowed to move when a stat moves. A check on the software's continued
## correctness is a regression test and belongs in tests/. The categories, and everything
## below stated as a rule, are gdd/systems/scenario-scripting/simulation-tests.md.
##
## TWO AUTHORING ROUTES, ONE RUNTIME. A scene built in the editor fills [member expectations]
## with [SimulationExpectation] resources; a parsed `sims/*.sim.yaml` spec produces its checks
## through SimArena. Both compile to the same `Array[SimulationCheck]`, so the fold, the
## window and the report are written once — the spec route is an instance of this class, not
## a sibling of it.
##
## THE WINDOW STARTS WHEN THE SCENARIO ARMS, not when the node enters the tree. Arming waits
## on the first navmesh sync, which is genuine boot rather than simulated time, and a check
## whose deadline was eaten by it would measure the engine instead of the game.

## Emitted once the run settles. `results` is one dictionary per check (see _build_results).
signal completed(all_passed: bool, results: Array)

#region Configuration
## The checks to run, authored as SimulationExpectation resources in the editor. Empty for a
## spec-driven run, which supplies its checks through _compile_checks() instead.
@export var expectations: Array[SimulationExpectation] = []

## Hard ceiling on the run in physics ticks, measured from arming. It is a BACKSTOP against a
## check that never settles, not the run window — see [member run_ticks].
@export var max_ticks: int = 4000

## The authored run window in physics ticks, measured from arming, or 0 for "no window of its
## own". With a window the run always plays it out; without one the run may stop as soon as
## every check has settled, which is the older editor-authored behaviour.
##
## Ticks rather than seconds HERE because this is the engine-facing edge: a spec authors
## `run: { for: 10s }` and SimArena converts once, through Engine.physics_ticks_per_second
## (`~/.claude/CLAUDE.md` §2.2 — convert at the boundary, derive the factor, never type it).
var run_ticks: int = 0
#endregion

#region State
var _manager: ScenarioTriggerManager
## The compiled leaves, in report order. Built once, at arming.
var _checks: Array[SimulationCheck] = []
## Folds the settled leaves into the run's verdict. Default: every leaf must pass, which is
## the implicit ALL an editor-authored scene means. A spec supplies its own, closing over the
## boolean tree it parsed.
var _verdict_resolver: Callable = Callable()
var _armed: bool = false
## The tick arming happened on; every deadline and the window are measured from it.
var _armed_tick: int = 0
var _finished: bool = false
var _all_passed: bool = false
#endregion


#region Lifecycle
func _ready() -> void:
	super()  # boot the real scenario: commanders, brains, scene entities, trigger manager
	if Engine.is_editor_hint():
		return
	_manager = _ensure_trigger_manager()
	# Arm once the navmesh is synced — mirrors ScenarioTriggerManager so any nav-dependent
	# check is safe, and anything that had to path has had somewhere to path over.
	_arm_when_navmesh_ready()


## Compile the checks, let a subclass act on a world that is now navigable, and start the
## window. Deliberately one method: the order of those three is the contract.
func _arm_when_navmesh_ready() -> void:
	if map != null and map.nav_manager != null and not map.nav_manager.is_ready():
		await map.nav_manager.navmesh_ready
	_checks = _compile_checks()
	_on_armed()
	_armed_tick = tick
	_armed = true
	if _checks.is_empty():
		_finish()  # nothing to check: a vacuously-passing run rather than a hang


func _physics_process(a_delta: float) -> void:
	super(a_delta)  # advances `tick` and runs the game
	if Engine.is_editor_hint() or _finished or not _armed:
		return
	var elapsed: int = tick - _armed_tick
	_on_tick(elapsed)
	for check: SimulationCheck in _checks:
		check.advance(elapsed)
	if _window_elapsed(elapsed) or _may_finish_early():
		_finish()


#endregion


#region Extension points
## Build the run's checks. The base implementation is the EDITOR route: each authored
## [SimulationExpectation] compiles to one liveness check. A spec-driven subclass overrides
## this and returns leaves bound to its own group roster.
func _compile_checks() -> Array[SimulationCheck]:
	var compiled: Array[SimulationCheck] = []
	for expectation: SimulationExpectation in expectations:
		if expectation == null:
			push_error("%s carries a null expectation" % name)
			continue
		compiled.append(expectation.compile(_manager))
	return compiled


## Called with a navigable world, after the checks exist and before the window starts. The
## place a spec-driven run issues its opening orders.
func _on_armed() -> void:
	pass


## Called every tick of the window, `a_elapsed` ticks after arming and before the checks
## sample it. The place a spec-driven run issues its timed orders.
func _on_tick(_a_elapsed: int) -> void:
	pass


#endregion


#region Resolution
## True once the authored window has played out, or the backstop has. `max_ticks` is checked
## unconditionally: a run whose checks never settle must still terminate.
func _window_elapsed(a_elapsed: int) -> bool:
	if run_ticks > 0 and a_elapsed >= run_ticks:
		return true
	return a_elapsed >= max_ticks


## A run may stop early only when every check has settled AND none of them is a mode whose
## meaning is the whole window. An at-end check is defined by the final tick and a safety
## check by every tick, so stopping early would be asserting something weaker than the spec
## says — the run would "pass" a truck that was alive at the moment we stopped looking.
func _may_finish_early() -> bool:
	if run_ticks > 0:
		return false
	for check: SimulationCheck in _checks:
		if check.needs_full_window() or not check.is_resolved():
			return false
	return true


func _finish() -> void:
	if _finished:
		return
	_finished = true
	var elapsed: int = tick - _armed_tick
	for check: SimulationCheck in _checks:
		check.finish(elapsed)
	_all_passed = _resolve_verdict()
	print(
		(
			"[SimulationScenario] %s — %s (%d ticks)"
			% [
				name,
				"PASS" if _all_passed else "FAIL",
				elapsed,
			]
		)
	)
	for check: SimulationCheck in _checks:
		print("    %s" % check.report_line())
	completed.emit(_all_passed, _build_results())


## The tree fold, or the implicit ALL when nothing supplied one.
func _resolve_verdict() -> bool:
	if _verdict_resolver.is_valid():
		return bool(_verdict_resolver.call(_checks))
	for check: SimulationCheck in _checks:
		if not check.passed():
			return false
	return true


## One dictionary per check, for a runner that wants the detail rather than the printout.
func _build_results() -> Array:
	var results: Array = []
	for check: SimulationCheck in _checks:
		(
			results
			. append(
				{
					"description": check.description,
					"passed": check.passed(),
					"met_tick": check.met_tick,
					"mode": check.mode,
					"measured": check.measured(),
				}
			)
		)
	return results


#endregion


#region Public API
## True once the run has settled. Lets a runner poll instead of awaiting the signal.
func is_finished() -> bool:
	return _finished


## The run's verdict — the tree fold, not "every leaf passed", which is only the default.
## Meaningless before is_finished().
func all_passed() -> bool:
	return _all_passed


func check_results() -> Array:
	return _build_results()
#endregion
