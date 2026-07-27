extends GutTest

## Unit tests for the temporal FOLD — the mechanism that turns a leaf's per-tick truth into
## one verdict, so a boolean tree can be resolved once at the end of a run.
##
## Three modes, one shape: an operator and a window.
##   AT_END    sample, at the final tick
##   LIVENESS  `or`,   until it holds, else until the deadline
##   SAFETY    `and`,  every tick
##
## Driven against a scripted truth sequence rather than a simulation: what is under test is
## the fold, not any matchup. See gdd/systems/scenario-scripting/simulation-tests.md.


## A predicate that returns the next value of `a_values` on each call, repeating the last one
## forever. Lets a test state the truth sequence it wants to fold.
class Sequence:
	extends RefCounted
	var values: Array[bool] = []
	var calls: int = 0

	func _init(a_values: Array[bool]) -> void:
		values = a_values

	func next() -> bool:
		var value: bool = values[mini(calls, values.size() - 1)]
		calls += 1
		return value


## A predicate whose answer the test sets directly — for modes that sample rather than fold.
class Holder:
	extends RefCounted
	var value: bool = false

	func _init(a_value: bool) -> void:
		value = a_value

	func read() -> bool:
		return value


#region At end
func test_at_end_ignores_everything_before_the_final_tick() -> void:
	# The mode's whole point: a claim about an OUTCOME is not disturbed by the run's middle.
	# A HOLDER rather than a Sequence here, precisely because an at-end check never calls its
	# predicate mid-run — a sequence would never advance, which is the behaviour below.
	var world := Holder.new(false)
	var check := SimulationCheck.new("outcome", world.read, SimulationCheck.Mode.AT_END)
	for tick: int in 3:
		check.advance(tick)
	assert_false(check.is_resolved(), "an at-end check does not settle early")
	world.value = true
	check.finish(3)
	assert_true(check.passed(), "sampled once, at the end")


func test_at_end_does_not_call_its_predicate_while_the_run_plays() -> void:
	var sequence := Sequence.new([true] as Array[bool])
	var check := SimulationCheck.new("outcome", sequence.next, SimulationCheck.Mode.AT_END)
	for tick: int in 5:
		check.advance(tick)
	assert_eq(sequence.calls, 0, "nothing is measured until the window elapses")
	check.finish(5)
	assert_eq(sequence.calls, 1)


func test_at_end_fails_when_false_at_the_end() -> void:
	var world := Holder.new(true)
	var check := SimulationCheck.new("outcome", world.read, SimulationCheck.Mode.AT_END)
	check.advance(0)
	check.advance(1)
	world.value = false
	check.finish(2)
	assert_false(check.passed(), "true earlier is not the claim an at-end check makes")
#endregion


#region Liveness
func test_liveness_passes_the_first_tick_it_holds() -> void:
	var sequence := Sequence.new([false, false, true] as Array[bool])
	var check := SimulationCheck.new("eventually", sequence.next, SimulationCheck.Mode.LIVENESS, 10)
	check.advance(0)
	check.advance(1)
	assert_false(check.is_resolved())
	check.advance(2)
	assert_true(check.is_resolved(), "it settles as soon as it holds")
	assert_true(check.passed())
	assert_eq(check.met_tick, 2, "the tick is reported for diagnosis")


func test_liveness_that_later_flips_back_still_passed() -> void:
	# `or` over the window: having happened is the claim, so a subsequent false is not a
	# retraction.
	var sequence := Sequence.new([true, false, false] as Array[bool])
	var check := SimulationCheck.new("eventually", sequence.next, SimulationCheck.Mode.LIVENESS, 10)
	check.advance(0)
	check.advance(1)
	check.advance(2)
	check.finish(2)
	assert_true(check.passed())


func test_liveness_fails_once_its_deadline_elapses() -> void:
	var sequence := Sequence.new([false] as Array[bool])
	var check := SimulationCheck.new("eventually", sequence.next, SimulationCheck.Mode.LIVENESS, 3)
	for tick: int in 4:
		check.advance(tick)
	assert_true(check.is_resolved())
	assert_false(check.passed())


func test_liveness_with_no_deadline_of_its_own_runs_to_the_window() -> void:
	var sequence := Sequence.new([false] as Array[bool])
	var check := SimulationCheck.new("eventually", sequence.next, SimulationCheck.Mode.LIVENESS, 0)
	for tick: int in 20:
		check.advance(tick)
	assert_false(check.is_resolved(), "0 means the run window is the deadline")
	check.finish(20)
	assert_false(check.passed())
#endregion


#region Safety
func test_safety_holds_when_never_violated() -> void:
	var sequence := Sequence.new([true] as Array[bool])
	var check := SimulationCheck.new("always", sequence.next, SimulationCheck.Mode.SAFETY)
	for tick: int in 10:
		check.advance(tick)
	check.finish(10)
	assert_true(check.passed())


func test_safety_fails_at_the_first_violation_and_stays_failed() -> void:
	# `and` over the window, starting true: one false is the verdict, and recovering afterwards
	# does not undo it. This is the mode that catches a truck whittled down and then repaired.
	var sequence := Sequence.new([true, true, false, true, true] as Array[bool])
	var check := SimulationCheck.new("always", sequence.next, SimulationCheck.Mode.SAFETY)
	for tick: int in 5:
		check.advance(tick)
	check.finish(5)
	assert_false(check.passed())
	assert_eq(check.met_tick, 2, "the violating tick is reported")


func test_safety_stops_measuring_once_violated() -> void:
	var sequence := Sequence.new([false] as Array[bool])
	var check := SimulationCheck.new("always", sequence.next, SimulationCheck.Mode.SAFETY)
	for tick: int in 5:
		check.advance(tick)
	assert_eq(sequence.calls, 1, "a settled check is not re-evaluated")
#endregion


#region What a mode says about the window
func test_only_liveness_can_end_a_run_early() -> void:
	# An at-end check is defined by the final tick and a safety check by every tick, so
	# stopping early would assert something weaker than the spec says.
	var always_true := func() -> bool: return true
	var liveness := SimulationCheck.new("a", always_true, SimulationCheck.Mode.LIVENESS)
	assert_false(liveness.needs_full_window())
	assert_true(SimulationCheck.new("b", always_true, SimulationCheck.Mode.AT_END).needs_full_window())
	assert_true(SimulationCheck.new("c", always_true, SimulationCheck.Mode.SAFETY).needs_full_window())


func test_an_unsettled_check_reports_itself_as_unsettled() -> void:
	var check := SimulationCheck.new("x", func() -> bool: return false, SimulationCheck.Mode.AT_END)
	assert_true(check.report_line().contains("never settled"))


func test_a_settled_check_reports_pass_or_fail_with_its_reason() -> void:
	var check := SimulationCheck.new("x", func() -> bool: return false, SimulationCheck.Mode.SAFETY)
	check.advance(4)
	check.finish(4)
	assert_true(check.report_line().contains("FAIL"))
	assert_true(check.report_line().contains("violated at tick 4"))
#endregion
