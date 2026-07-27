class_name SimulationExpectation
extends Resource

## One check against a running [SimulationScenario]: a [Condition] that must become true
## before a deadline. Authored in the editor as an element of
## SimulationScenario.expectations.
##
## Semantics are LIVENESS ("eventually, by a deadline"): the expectation PASSES the first
## physics tick its condition reports true, as long as that happens at or before
## [member deadline_ticks]; it FAILS the tick the deadline elapses still untrue. A
## condition that becomes true and later flips back still counts as passed — it was
## satisfied in time. This matches checks like "before 300 ticks the drone should have an
## Attack command" or "before 3000 ticks every scout point should have been seen".
##
## Conditions reuse the scenario Condition module, so any existing Condition works and new
## checks are just new Condition subclasses (e.g. ConditionUnitHasCommand,
## ConditionScoutCoverage).

## Human-readable label shown in the run report.
@export var description: String = ""

## The check to satisfy. Any Condition subclass.
@export var condition: Condition

## Physics-tick budget: the condition must be met at or before this many ticks after the
## scenario starts. 0 means "no deadline" — it's only required to be true by the scenario's
## max_ticks ceiling.
@export var deadline_ticks: int = 0


## Compile to the runtime leaf the scenario actually folds.
##
## The condition is RESET before arming because expectation conditions are shared
## sub-resources like a trigger's, so a second run of the same scene in one process would
## otherwise inherit the first run's state — see
## ScenarioTriggerManager._reset_session_conditions().
##
## Always a LIVENESS check: that is what `deadline_ticks` means and what this resource has
## always asserted. An at-end or safety claim is expressible in a `sims/*.sim.yaml` spec,
## which is the other producer of a SimulationCheck.
func compile(a_manager: ScenarioTriggerManager) -> SimulationCheck:
	if condition == null:
		# A leaf with no predicate is a spec error, not a passing check. Fail it loudly and
		# let the run report say which one.
		push_error("SimulationExpectation '%s' names no condition" % description)
		return SimulationCheck.new(
			"%s <no condition>" % description, func() -> bool: return false,
			SimulationCheck.Mode.LIVENESS, deadline_ticks
		)
	condition.reset()
	condition.arm(a_manager)
	var predicate: Callable = func() -> bool: return condition.evaluate(a_manager)
	return SimulationCheck.new(
		description, predicate, SimulationCheck.Mode.LIVENESS, deadline_ticks
	)
