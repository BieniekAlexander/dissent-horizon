class_name TestScenario
extends Scenario

## A Scenario you author in the editor to TEST the bot's behaviour end-to-end.
##
## Build the situation the way you build any scenario — place the Commandables in the scene
## (each tagged with the owning commander via [member Entity.default_commander_id]) and give
## them whatever initial commands the scene needs — then author the checks in
## [member expectations]. When run, it boots the REAL game (commanders, BotBrains, the full
## perception → decision → action loop) and watches each expectation, recording pass/fail.
##
## Each expectation is a [TestExpectation]: a [Condition] plus a deadline in physics ticks.
## The condition must become true before its deadline. Conditions reuse the scenario
## Condition module, so new things to check are just new Condition subclasses.
##
## Run it headlessly through the generic runner (tests/test_BotTestScenarios.gd), which
## loads each TestScenario scene, runs it, and asserts every expectation passed. The scene
## emits [signal completed] when every expectation has resolved (or max_ticks is hit).

## Emitted once every expectation has resolved (passed or failed), or [member max_ticks] is
## reached. `results` is one dictionary per expectation (see _build_results).
signal completed(all_passed: bool, results: Array)

## The checks to run, authored as TestExpectation resources in the editor.
@export var expectations: Array[TestExpectation] = []

## Hard ceiling on the run so an expectation that never resolves (e.g. deadline 0, or a
## bug) still terminates the scenario. Set above the largest deadline you author.
@export var max_ticks: int = 4000

enum Status { PENDING, PASSED, FAILED }

var _manager: ScenarioTriggerManager
var _status: Array[int] = []          ## per-expectation Status
var _met_tick: Array[int] = []        ## physics tick each expectation passed, else -1
var _armed: bool = false
var _finished: bool = false


func _ready() -> void:
	super()  # boot the real scenario: commanders, brains, scene entities, trigger manager
	if Engine.is_editor_hint():
		return
	_manager = _ensure_trigger_manager()
	_status.resize(expectations.size())
	_status.fill(Status.PENDING)
	_met_tick.resize(expectations.size())
	_met_tick.fill(-1)
	# Arm conditions once the navmesh is synced — mirrors ScenarioTriggerManager so any
	# nav-dependent condition is safe, and the bot has begun acting by the time we watch.
	_arm_when_navmesh_ready()
	if expectations.is_empty():
		_finish()  # nothing to check: a vacuously-passing run rather than a hang


## Arm every expectation's condition (push conditions subscribe to their bus; pull
## conditions register with the poller) after the navmesh first synchronizes.
func _arm_when_navmesh_ready() -> void:
	if map != null and map.nav_manager != null and not map.nav_manager.is_ready():
		await map.nav_manager.navmesh_ready
	for e: TestExpectation in expectations:
		if e != null and e.condition != null:
			e.condition.arm(_manager)
	_armed = true


func _physics_process(delta: float) -> void:
	super(delta)  # advances `frame` and runs the game
	if Engine.is_editor_hint() or _finished or not _armed:
		return
	_evaluate_expectations()


## Resolve each still-pending expectation against the current tick. An expectation passes
## the first tick its condition is true; it fails once its deadline (or max_ticks) elapses
## untrue. We read truth via Condition.evaluate() — lag-free for both pull (live) and push
## (cached, updated by the armed handler) conditions. Finishes the run once none remain.
func _evaluate_expectations() -> void:
	var pending: int = 0
	for i: int in expectations.size():
		if _status[i] != Status.PENDING:
			continue
		var e: TestExpectation = expectations[i]
		if e == null or e.condition == null:
			_status[i] = Status.FAILED
			continue
		if e.condition.evaluate(_manager):
			_status[i] = Status.PASSED
			_met_tick[i] = frame
		elif (e.deadline_ticks > 0 and frame >= e.deadline_ticks) or frame >= max_ticks:
			_status[i] = Status.FAILED
		else:
			pending += 1
	if pending == 0:
		_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	var results: Array = _build_results()
	var all_passed: bool = results.all(func(r: Dictionary) -> bool: return r["passed"])
	print("[TestScenario] %s — %s" % [name, "PASS" if all_passed else "FAIL"])
	for r: Dictionary in results:
		var detail: String = "met at tick %d" % r["met_tick"] if r["passed"] \
			else ("deadline %d elapsed" % r["deadline_ticks"] if r["deadline_ticks"] > 0 else "never met")
		print("    [%s] %s (%s)" % ["PASS" if r["passed"] else "FAIL", r["description"], detail])
	completed.emit(all_passed, results)


func _build_results() -> Array:
	var results: Array = []
	for i: int in expectations.size():
		var e: TestExpectation = expectations[i]
		results.append({
			"description": e.description if e != null else "<null expectation>",
			"passed": _status[i] == Status.PASSED,
			"met_tick": _met_tick[i],
			"deadline_ticks": e.deadline_ticks if e != null else 0,
		})
	return results


## True once the run has resolved every expectation (or hit max_ticks). Lets a runner poll
## instead of awaiting the signal.
func is_finished() -> bool:
	return _finished
