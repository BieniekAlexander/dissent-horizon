extends GutTest

## Regression: a scenario re-entered from the menu used to inherit the PREVIOUS run's
## condition state.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_ConditionResidue.gd -gexit
##
## A Condition is a Resource, and a sub-resource authored inside a .tscn is SHARED by every
## instantiation of that scene rather than copied per instance — the first test below pins
## that engine behaviour down, since everything else here exists because of it. The fix is
## ScenarioTriggerManager._reset_session_conditions(), which resets every authored condition
## once at scenario start; the tests after it cover what that has to clear, and the one case
## it must NOT touch (a trigger re-armed mid-session).

const SECONDS: float = 5.0

var _scenario: Scenario
var _manager: ScenarioTriggerManager


## A condition whose result is set directly by the test, counting its own resets — same
## idiom as test_Triggers.gd.
class StubCondition:
	extends Condition
	var result: bool = false
	var reset_count: int = 0

	func evaluate(_a_manager: ScenarioTriggerManager) -> bool:
		return result

	func reset() -> void:
		super.reset()
		reset_count += 1


func before_each() -> void:
	# Never added to the tree: _ready would build a whole session, and all a ConditionTimer
	# wants from it is `frame`, which the tests drive by hand (as test_TriggerSimultaneousFire
	# does).
	_scenario = Scenario.new()
	_scenario.tick = 0


func after_each() -> void:
	if _manager != null and _manager.simulation_clock != null:
		_manager.simulation_clock.clear()
	if _scenario != null:
		_scenario.free()
	get_tree().paused = false


func _timer(a_seconds: float, a_mode: ConditionTimer.Mode) -> ConditionTimer:
	var condition := ConditionTimer.new()
	condition.mode = a_mode
	condition.seconds_expression = str(a_seconds)
	return condition


func _trigger(a_conditions: Array[Condition], a_trigger_name: String) -> GlobalTrigger:
	var trigger := GlobalTrigger.new()
	trigger.name = a_trigger_name
	trigger.one_shot = true
	trigger.conditions = a_conditions
	return trigger


## Build a manager owning `triggers` and arm them, the way a scenario does. They must be
## children BEFORE the manager enters the tree — _ready is what collects them and what runs
## the session reset.
func _build(a_triggers: Array) -> void:
	_manager = ScenarioTriggerManager.new()
	for trigger: GlobalTrigger in a_triggers:
		_manager.add_child(trigger)
	add_child_autofree(_manager)
	assert_push_warning("expected parent to be Scenario")
	_manager.scenario = _scenario
	for trigger: GlobalTrigger in a_triggers:
		if trigger.enabled:
			trigger.arm(_manager)


## One physics tick of the pull-condition poller, at the current scenario frame.
func _tick() -> void:
	_manager.condition_poller._physics_process(0.0)


# --- The premise ---------------------------------------------------------------


func test_condition_subresources_are_shared_between_scene_instances() -> void:
	# Why any of this is needed: instantiating a scene twice does NOT give each instance its
	# own copy of an authored sub-resource, so the second run of a scenario gets the first
	# run's live Condition objects, mutations and all.
	var authored := _trigger([_timer(SECONDS, ConditionTimer.Mode.COUNTDOWN)], "Authored")
	var packed := PackedScene.new()
	packed.pack(authored)
	authored.free()

	var first := packed.instantiate() as GlobalTrigger
	var second := packed.instantiate() as GlobalTrigger
	var from_first: Condition = first.conditions[0]
	var from_second: Condition = second.conditions[0]
	assert_eq(
		from_first.get_instance_id(),
		from_second.get_instance_id(),
		"two instances of one scene share the same Condition object"
	)

	from_first._last = true
	assert_true(from_second._last, "so runtime state written by one run is visible to the next")
	first.free()
	second.free()


# --- What the session reset clears ---------------------------------------------


func test_a_countdown_left_running_restarts_from_the_new_session() -> void:
	var timer := _timer(SECONDS, ConditionTimer.Mode.COUNTDOWN)
	# As a previous session left it: counting from a frame number this session will not
	# reach for another three minutes.
	timer._start_tick = 5000
	timer._target_ticks = TimeUtils.ticks_from_seconds(SECONDS)
	timer._last = true
	_build([_trigger([timer] as Array[Condition], "Countdown")])

	assert_eq(timer._start_tick, -1, "the stale start frame is dropped at scenario start")
	assert_false(timer._last, "as is the truth it was caching")

	_scenario.tick = 0
	_tick()
	assert_false(timer.is_met(), "the countdown restarts against this session's clock")
	_scenario.tick = TimeUtils.ticks_from_seconds(SECONDS)
	_tick()
	assert_true(timer.is_met(), "and lands SECONDS into the new session, not 5000 frames in")


func test_a_resolved_interval_is_re_rolled_for_the_new_session() -> void:
	var timer := _timer(SECONDS, ConditionTimer.Mode.ELAPSED_SINCE_START)
	# A previous session's roll of an expression like "15 + randi_range(0, 10)" — cached for
	# the rest of that run by design, but it must not outlive the run.
	timer._target_ticks = 999999
	_build([_trigger([timer] as Array[Condition], "Elapsed")])

	assert_eq(timer._target_ticks, -1, "the cached deadline is dropped at scenario start")
	_scenario.tick = TimeUtils.ticks_from_seconds(SECONDS)
	_tick()
	assert_true(timer.is_met(), "so the new session resolves its own interval")


func test_a_stale_cached_truth_cannot_fire_a_trigger_on_the_first_tick() -> void:
	# The user-visible symptom: the timer is not the condition that CHANGES, so nothing
	# re-evaluates it before the AND aggregate reads its cached truth. A timer left `true`
	# by the previous run made a two-condition trigger fire the moment its other condition
	# came true — with the timer's own 5 seconds never counted at all.
	var timer := _timer(SECONDS, ConditionTimer.Mode.ELAPSED_SINCE_START)
	timer._last = true
	var other := StubCondition.new()
	var trigger := _trigger([timer, other] as Array[Condition], "Both")
	var fired: Array[bool] = []
	trigger.fired.connect(func() -> void: fired.append(true))
	_build([trigger])

	other.result = true
	_scenario.tick = 1
	_tick()
	assert_eq(fired.size(), 0, "the trigger waits for the timer instead of firing on its residue")

	_scenario.tick = TimeUtils.ticks_from_seconds(SECONDS)
	_tick()
	assert_eq(fired.size(), 1, "and fires once the timer genuinely elapses")


func test_tactic_rule_conditions_are_reset_too() -> void:
	var condition := StubCondition.new()
	var rule := TacticRule.new()
	rule.condition = condition
	var tactic := ScenarioTactic.new()
	tactic.unit_group = &"test_condition_residue"
	tactic.add_child(rule)

	_manager = ScenarioTriggerManager.new()
	_manager.add_child(tactic)
	add_child_autofree(_manager)
	assert_push_warning("expected parent to be Scenario")

	assert_eq(condition.reset_count, 1, "a tactic's rule conditions are session state as well")


# --- What it must NOT clear -----------------------------------------------------


func test_re_arming_mid_session_keeps_accumulated_state() -> void:
	# An EventChainTrigger switching a trigger off and on again is not a new session: a
	# ConditionOccurrenceTally's running count is meant to survive it. This is why the reset
	# lives in the manager rather than in GlobalTrigger.arm().
	var condition := StubCondition.new()
	var trigger := _trigger([condition] as Array[Condition], "Rearmed")
	_build([trigger])
	assert_eq(condition.reset_count, 1, "reset once, at scenario start")

	trigger.set_active(false, _manager)
	trigger.set_active(true, _manager)
	assert_eq(condition.reset_count, 1, "and not again when the trigger is re-armed")
