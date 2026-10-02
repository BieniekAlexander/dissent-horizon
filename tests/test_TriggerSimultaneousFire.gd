extends GutTest

## Reproduction for: two GlobalTriggers with identical COUNTDOWN timers and the same
## prerequisites, where only the first fires.
##
## Run with:
## godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_TriggerSimultaneousFire.gd
## -gexit

const SECONDS: float = 5.0

var _scenario: Scenario
var _manager: ScenarioTriggerManager


func before_each() -> void:
	# Never added to the tree: _ready would build commanders and a whole session, and all a
	# ConditionTimer wants from it is `frame`, which the tests below drive by hand.
	_scenario = Scenario.new()
	_scenario.tick = 0


func after_each() -> void:
	if _manager != null and _manager.simulation_clock != null:
		_manager.simulation_clock.clear()
	if _scenario != null:
		_scenario.free()
	get_tree().paused = false


func _timer(a_seconds: float) -> ConditionTimer:
	var condition := ConditionTimer.new()
	condition.mode = ConditionTimer.Mode.COUNTDOWN
	condition.seconds_expression = str(a_seconds)
	return condition


func _trigger(a_condition: Condition, a_trigger_name: String) -> GlobalTrigger:
	var trigger := GlobalTrigger.new()
	trigger.name = a_trigger_name
	trigger.one_shot = true
	trigger.conditions = [a_condition]
	return trigger


## Build a manager owning `triggers`. They must be children before the manager enters the
## tree, because _ready is what collects them into global_triggers.
func _build(a_triggers: Array) -> void:
	_manager = ScenarioTriggerManager.new()
	for trigger: GlobalTrigger in a_triggers:
		_manager.add_child(trigger)
	add_child_autofree(_manager)
	assert_push_warning("expected parent to be Scenario")
	_manager.scenario = _scenario
	for trigger: GlobalTrigger in a_triggers:
		trigger.arm(_manager)


## One physics tick of the pull-condition poller, at the current scenario frame.
func _tick() -> void:
	_manager.condition_poller._physics_process(0.0)


func test_two_identical_countdowns_both_fire() -> void:
	var a := _trigger(_timer(SECONDS), "A")
	var b := _trigger(_timer(SECONDS), "B")
	_build([a, b])

	# Frame 0 starts both countdowns (COUNTDOWN latches _start_tick on first evaluate).
	_tick()
	assert_false(a.has_fired, "not due yet")
	assert_false(b.has_fired, "not due yet")

	# Jump past the shared deadline: both conditions are now true on the SAME tick.
	_scenario.tick = TimeUtils.ticks_from_seconds(SECONDS) + 1
	_tick()

	assert_true(a.has_fired, "the first trigger fires")
	assert_true(b.has_fired, "the second trigger fires on the same tick")


func test_two_identical_countdowns_both_fire_within_a_few_ticks() -> void:
	# Softer version of the above: even allowing several ticks, does B ever fire?
	var a := _trigger(_timer(SECONDS), "A")
	var b := _trigger(_timer(SECONDS), "B")
	_build([a, b])
	_tick()

	_scenario.tick = TimeUtils.ticks_from_seconds(SECONDS) + 1
	for _i: int in 5:
		_tick()

	assert_true(a.has_fired, "the first trigger fires")
	assert_true(b.has_fired, "the second trigger fires eventually")


func test_staggered_countdowns_both_fire() -> void:
	# The configuration the author fell back on: different durations, which works.
	var a := _trigger(_timer(SECONDS), "A")
	var b := _trigger(_timer(SECONDS * 3.0), "B")
	_build([a, b])
	_tick()

	_scenario.tick = TimeUtils.ticks_from_seconds(SECONDS) + 1
	_tick()
	assert_true(a.has_fired, "the short timer fires first")
	assert_false(b.has_fired, "the long one is still counting")

	_scenario.tick = TimeUtils.ticks_from_seconds(SECONDS * 3.0) + 1
	_tick()
	assert_true(b.has_fired, "the long timer fires later")


func test_three_identical_countdowns_all_fire() -> void:
	# Three, to show how far the skip propagates if one is being dropped per tick.
	var a := _trigger(_timer(SECONDS), "A")
	var b := _trigger(_timer(SECONDS), "B")
	var c := _trigger(_timer(SECONDS), "C")
	_build([a, b, c])
	_tick()

	_scenario.tick = TimeUtils.ticks_from_seconds(SECONDS) + 1
	_tick()

	assert_true(a.has_fired, "A fires")
	assert_true(b.has_fired, "B fires")
	assert_true(c.has_fired, "C fires")


# --- Does a dialog hold stall the poller? ---------------------------------------


func test_the_poller_keeps_running_while_a_dialog_holds_the_simulation() -> void:
	# TimeSinceLiberation shows a dialog, which takes a SimulationClock hold and pauses the
	# tree. If that stopped the poller, any trigger that had not yet fired would stall until
	# the player dismissed the window — which would read as "it never activated".
	var a := _trigger(_timer(SECONDS), "A")
	_build([a])

	_manager.simulation_clock.hold("test_dialog")
	assert_true(get_tree().paused, "the hold paused the tree")
	assert_true(
		_manager.condition_poller.can_process(),
		"the poller must keep evaluating while the world is held"
	)


# --- The "Start" trigger shape --------------------------------------------------


## Both s1 and s2 open with a trigger named "Start": one ConditionTimer left at its
## default mode (ELAPSED_SINCE_START) with seconds = 0.0, condition_mode = OR. It is meant
## to run unconditionally on the first tick of the scenario.
func _start_shaped_trigger() -> GlobalTrigger:
	var condition := ConditionTimer.new()
	condition.seconds_expression = "0"  # mode left at its default, as authored
	var trigger := GlobalTrigger.new()
	trigger.name = "Start"
	trigger.one_shot = true
	trigger.condition_mode = GlobalTrigger.ConditionMode.OR
	trigger.conditions = [condition]
	return trigger


func test_a_zero_second_start_trigger_fires_on_the_first_tick() -> void:
	var start := _start_shaped_trigger()
	_build([start])

	_tick()

	assert_true(start.has_fired, "an unconditional Start trigger runs at scenario start")
