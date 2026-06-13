extends GutTest

## Tests for the Node3D-based scenario event system.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_ScenarioEvents.gd
##
## Covers Trigger node logic, ScenarioEventManager child collection, the
## EventCommandPoint command-type mapping, and EventChainTrigger enable/disable.


## A condition whose result is set directly by the test.
class StubCondition extends Condition:
	var result: bool = false
	var reset_count: int = 0
	func evaluate(_manager: ScenarioEventManager) -> bool:
		return result
	func reset() -> void:
		reset_count += 1


## An event that records how many times it was executed.
class StubEvent extends ScenarioEvent:
	var fire_count: int = 0
	func execute(_manager: ScenarioEventManager) -> void:
		fire_count += 1


func _make_trigger() -> Trigger:
	var t := Trigger.new()
	add_child_autofree(t)
	return t


# --- Trigger condition evaluation -------------------------------------------

func test_empty_conditions_is_never_satisfied() -> void:
	var t := _make_trigger()
	assert_false(t.is_satisfied(null), "no conditions should never fire")


func test_and_mode_requires_all_conditions() -> void:
	var t := _make_trigger()
	var c1 := StubCondition.new()
	var c2 := StubCondition.new()
	t.conditions = [c1, c2]
	t.condition_mode = Trigger.ConditionMode.AND
	c1.result = true
	c2.result = false
	assert_false(t.is_satisfied(null), "AND fails when one condition is false")
	c2.result = true
	assert_true(t.is_satisfied(null), "AND passes when all conditions are true")


func test_or_mode_requires_any_condition() -> void:
	var t := _make_trigger()
	var c1 := StubCondition.new()
	var c2 := StubCondition.new()
	t.conditions = [c1, c2]
	t.condition_mode = Trigger.ConditionMode.OR
	c1.result = false
	c2.result = false
	assert_false(t.is_satisfied(null), "OR fails when no condition is true")
	c2.result = true
	assert_true(t.is_satisfied(null), "OR passes when any condition is true")


# --- Trigger firing ----------------------------------------------------------

func test_fire_executes_all_events() -> void:
	var t := _make_trigger()
	var e1 := StubEvent.new()
	var e2 := StubEvent.new()
	add_child_autofree(e1)
	add_child_autofree(e2)
	t.events = [e1, e2]
	t.fire(null)
	assert_eq(e1.fire_count, 1, "first event fired once")
	assert_eq(e2.fire_count, 1, "second event fired once")


func test_one_shot_disables_after_firing() -> void:
	var t := _make_trigger()
	t.one_shot = true
	t.enabled = true
	t.fire(null)
	assert_false(t.enabled, "one-shot trigger disables itself after firing")


func test_repeating_trigger_resets_conditions() -> void:
	var t := _make_trigger()
	t.one_shot = false
	var c := StubCondition.new()
	t.conditions = [c]
	t.fire(null)
	assert_true(t.enabled, "repeating trigger stays enabled")
	assert_eq(c.reset_count, 1, "repeating trigger resets its conditions")


# --- Manager child collection ------------------------------------------------

func test_manager_collects_trigger_children_in_order() -> void:
	var manager := ScenarioEventManager.new()
	var a := Trigger.new()
	a.name = "A"
	var b := Trigger.new()
	b.name = "B"
	b.starts_disabled = true
	# Interleave a non-trigger event node to confirm it's filtered out.
	var event := StubEvent.new()
	manager.add_child(a)
	manager.add_child(event)
	manager.add_child(b)
	add_child_autofree(manager)  # triggers _ready → collection
	# _ready warns because the test parents the manager under the GutTest node
	# rather than a Scenario; that warning is expected here and unrelated to the
	# child-collection behaviour under test.
	assert_engine_error("expected parent to be Scenario")

	assert_eq(manager.triggers.size(), 2, "only Trigger children are collected")
	assert_eq(manager.triggers[0], a, "collection preserves scene-tree order")
	assert_eq(manager.triggers[1], b)
	assert_true(a.enabled, "trigger without starts_disabled is enabled")
	assert_false(b.enabled, "starts_disabled trigger begins disabled")
	assert_eq(manager.active_trigger_count(), 1, "only enabled triggers are active")


# --- EventCommandPoint -------------------------------------------------------

func test_command_point_default_is_attack_move() -> void:
	var p := EventCommandPoint.new()
	add_child_autofree(p)
	assert_eq(p.command_type, "attack_move", "default command type is attack_move")


# --- EventChainTrigger -------------------------------------------------------

func test_chain_trigger_toggles_target() -> void:
	var target := _make_trigger()
	target.enabled = false
	var chain := EventChainTrigger.new()
	add_child_autofree(chain)
	chain.target_trigger = target
	chain.enable = true
	chain.execute(null)
	assert_true(target.enabled, "chain event enables its target trigger")
	chain.enable = false
	chain.execute(null)
	assert_false(target.enabled, "chain event disables its target trigger")
