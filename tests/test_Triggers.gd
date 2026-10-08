extends GutTest

## Tests for the unified scenario trigger system.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_Triggers.gd
##
## Covers GlobalTrigger watcher logic (condition evaluation, one-shot/repeat),
## ScenarioTriggerManager child collection, ConditionOccurrenceTally signal accumulation,
## the EventCommandPoint command-type mapping, and EventChainTrigger enable/disable.


## A condition whose result is set directly by the test.
class StubCondition:
	extends Condition
	var result: bool = false
	var reset_count: int = 0

	func evaluate(_a_manager: ScenarioTriggerManager) -> bool:
		return result

	func reset() -> void:
		reset_count += 1


## An event that records how many times it was executed (used as an interleaved
## non-GlobalTrigger child to confirm the manager filters it out).
class StubEvent:
	extends AbstractEvent
	var fire_count: int = 0

	func execute(_a_manager: ScenarioTriggerManager) -> void:
		fire_count += 1


func _make_global_event() -> GlobalTrigger:
	var e := GlobalTrigger.new()
	add_child_autofree(e)
	return e


# --- GlobalTrigger condition evaluation ---------------------------------------


func test_no_conditions_is_satisfied_immediately() -> void:
	var e := _make_global_event()
	assert_true(e.is_satisfied(null), "a trigger with nothing to wait for is satisfied")
	assert_true(e.is_unconditional(), "and knows it is unconditional")


func test_blank_condition_rows_are_ignored() -> void:
	# An Array export grows an empty row whenever it is extended in the inspector, so a lone
	# blank row means "unauthored", not "an unmeetable condition".
	var e := _make_global_event()
	e.conditions = [null] as Array[Condition]
	assert_true(e.is_unconditional(), "a blank row does not count as a condition")
	assert_true(e.is_satisfied(null), "so the trigger still fires immediately")


func test_blank_row_alongside_a_real_condition_is_skipped() -> void:
	var e := _make_global_event()
	var c := StubCondition.new()
	e.conditions = [null, c] as Array[Condition]
	e.condition_mode = GlobalTrigger.ConditionMode.AND
	assert_false(e.is_unconditional(), "one real condition is enough to gate the trigger")
	assert_false(e.is_satisfied(null), "and the blank row neither blocks nor satisfies it")
	c.result = true
	assert_true(e.is_satisfied(null))


func test_and_mode_requires_all_conditions() -> void:
	var e := _make_global_event()
	var c1 := StubCondition.new()
	var c2 := StubCondition.new()
	e.conditions = [c1, c2]
	e.condition_mode = GlobalTrigger.ConditionMode.AND
	c1.result = true
	c2.result = false
	assert_false(e.is_satisfied(null), "AND fails when one condition is false")
	c2.result = true
	assert_true(e.is_satisfied(null), "AND passes when all conditions are true")


func test_or_mode_requires_any_condition() -> void:
	var e := _make_global_event()
	var c1 := StubCondition.new()
	var c2 := StubCondition.new()
	e.conditions = [c1, c2]
	e.condition_mode = GlobalTrigger.ConditionMode.OR
	c1.result = false
	c2.result = false
	assert_false(e.is_satisfied(null), "OR fails when no condition is true")
	c2.result = true
	assert_true(e.is_satisfied(null), "OR passes when any condition is true")


# --- GlobalTrigger firing ------------------------------------------------------
# fire() runs the trigger's inline child events; with no child events here, fire is a
# no-op (guarded), so a bare (untreed) manager is enough to exercise the
# one-shot / repeat bookkeeping without a Scenario or Map.


func test_one_shot_disables_after_firing() -> void:
	var mgr := ScenarioTriggerManager.new()
	autofree(mgr)
	var e := _make_global_event()
	e.one_shot = true
	e.enabled = true
	e.fire(mgr)
	assert_false(e.enabled, "one-shot event disables itself after firing")


func test_repeating_event_resets_conditions() -> void:
	var mgr := ScenarioTriggerManager.new()
	autofree(mgr)
	var e := _make_global_event()
	e.one_shot = false
	var c := StubCondition.new()
	e.conditions = [c]
	e.fire(mgr)
	assert_true(e.enabled, "repeating event stays enabled")
	assert_eq(c.reset_count, 1, "repeating event resets its conditions")


func test_no_conditions_disables_after_firing_even_when_repeating() -> void:
	# Honouring one_shot = false here would re-fire every other frame forever: the stand-in
	# condition is true again the moment reset() clears the edge latch.
	var mgr := ScenarioTriggerManager.new()
	autofree(mgr)
	var e := _make_global_event()
	e.one_shot = false
	e.enabled = true
	e.fire(mgr)
	assert_false(e.enabled, "an unconditional trigger is one-shot whatever the flag says")


# --- Unconditional triggers: the driver ---------------------------------------
# The other tests call fire() directly. This one goes through the real arming path — manager
# _ready → _arm_triggers → ConditionPoller — because "fires with no conditions" is exactly the
# claim that has no driver unless the stand-in condition registers with the poller.


func test_unconditional_trigger_fires_once_through_the_poller() -> void:
	var manager := ScenarioTriggerManager.new()
	var trigger := GlobalTrigger.new()
	trigger.name = "Unconditional"
	var event := StubEvent.new()
	trigger.add_child(event)
	manager.add_child(trigger)
	add_child_autofree(manager)  # _ready → arms every enabled trigger (no Map: no navmesh await)
	assert_push_warning("expected parent to be Scenario")

	assert_eq(event.fire_count, 0, "arming alone does not run the events")
	await wait_physics_frames(1)
	assert_eq(event.fire_count, 1, "the first poll fires it")
	await wait_physics_frames(3)
	assert_eq(event.fire_count, 1, "and it does not re-fire on later frames")
	assert_true(trigger.has_fired)
	assert_eq(manager.active_global_trigger_count(), 0, "it stops counting as pending")


func test_unconditional_trigger_refires_when_rearmed() -> void:
	# The on-demand case: an EventChainTrigger switching it back on. Without resetting the
	# stand-in's cached truth there is no rising edge and the re-armed trigger sits inert.
	var manager := ScenarioTriggerManager.new()
	var trigger := GlobalTrigger.new()
	trigger.name = "Unconditional"
	var event := StubEvent.new()
	trigger.add_child(event)
	manager.add_child(trigger)
	add_child_autofree(manager)
	assert_push_warning("expected parent to be Scenario")

	await wait_physics_frames(1)
	assert_eq(event.fire_count, 1)
	trigger.set_active(true, manager)
	await wait_physics_frames(1)
	assert_eq(event.fire_count, 2, "re-arming fires it again")


# --- Manager child collection ------------------------------------------------


func test_manager_collects_global_event_children_in_order() -> void:
	var manager := ScenarioTriggerManager.new()
	var a := GlobalTrigger.new()
	a.name = "A"
	var b := GlobalTrigger.new()
	b.name = "B"
	b.prerequisites = [a] as Array[GlobalTrigger]
	# Interleave a non-GlobalTrigger node to confirm it's filtered out.
	var event := StubEvent.new()
	manager.add_child(a)
	manager.add_child(event)
	manager.add_child(b)
	add_child_autofree(manager)  # triggers _ready → collection
	# _ready warns because the test parents the manager under the GutTest node
	# rather than a Scenario; that warning is expected and unrelated to the
	# child-collection behaviour under test.
	assert_push_warning("expected parent to be Scenario")

	assert_eq(manager.global_triggers.size(), 2, "only GlobalTrigger children are collected")
	assert_eq(manager.global_triggers[0], a, "collection preserves scene-tree order")
	assert_eq(manager.global_triggers[1], b)
	assert_true(a.enabled, "an ungated trigger is enabled")
	assert_false(b.enabled, "one waiting on a prerequisite begins disabled")
	assert_eq(manager.active_global_trigger_count(), 1, "only enabled events are active")


# --- ConditionOccurrenceTally -----------------------------------------------------


func test_event_tally_accumulates_via_signal() -> void:
	var mgr := ScenarioTriggerManager.new()
	autofree(mgr)
	var t := ConditionOccurrenceTally.new()
	t.occurrence = Entity.EntityOccurrence.ON_DEATH
	t.commander_id = -1  # any commander
	t.count = 2
	t.arm(mgr)  # push: subscribe to the entity_occurrence bus
	assert_false(t.evaluate(mgr), "tally starts below the threshold")
	mgr.report_entity_occurrence(Entity.EntityOccurrence.ON_DEATH, null)
	assert_false(t.evaluate(mgr), "one occurrence is still below the threshold")
	mgr.report_entity_occurrence(Entity.EntityOccurrence.ON_DEATH, null)
	assert_true(t.evaluate(mgr), "threshold met after the second occurrence")
	# A non-matching occurrence type must not count.
	mgr.report_entity_occurrence(Entity.EntityOccurrence.ON_RECEIVE_DAMAGE, null)
	t.count = 3
	assert_false(t.evaluate(mgr), "wrong occurrence type does not advance the tally")


# --- Push firing path: a trigger fires reactively when its condition crosses ----


func test_push_trigger_fires_when_tally_condition_met() -> void:
	var mgr := ScenarioTriggerManager.new()
	autofree(mgr)
	var trigger := _make_global_event()
	var tally := ConditionOccurrenceTally.new()
	tally.occurrence = Entity.EntityOccurrence.ON_DEATH
	tally.commander_id = -1
	tally.count = 2
	trigger.conditions = [tally]
	trigger.one_shot = true
	trigger.arm(mgr)  # no poll loop — the trigger watches its condition via signal
	mgr.report_entity_occurrence(Entity.EntityOccurrence.ON_DEATH, null)
	assert_true(trigger.enabled, "trigger has not fired after 1 of 2 occurrences")
	mgr.report_entity_occurrence(Entity.EntityOccurrence.ON_DEATH, null)
	assert_false(trigger.enabled, "one-shot trigger fired (disabled) after 2 of 2 occurrences")


# --- Pull driver: edge-detected poll ----------------------------------------


func test_poll_emits_state_changed_only_on_edges() -> void:
	var c := StubCondition.new()
	watch_signals(c)
	c.poll(null)  # false → false: no edge
	assert_signal_emit_count(c, "state_changed", 0)
	c.result = true
	c.poll(null)  # false → true: rising edge
	assert_signal_emit_count(c, "state_changed", 1)
	c.poll(null)  # true → true: steady, no emit
	assert_signal_emit_count(c, "state_changed", 1)
	assert_true(c.is_met(), "is_met() reflects the last polled truth")


# --- EventCommandPoint -------------------------------------------------------


func test_command_point_default_is_attack_move() -> void:
	var p := EventCommandPoint.new()
	add_child_autofree(p)
	assert_eq(p.command_type, "attack_move", "default command type is attack_move")


# --- EventChainTrigger -------------------------------------------------------


func test_chain_trigger_toggles_target() -> void:
	var target := _make_global_event()
	target.enabled = false
	var chain := EventChainTrigger.new()
	add_child_autofree(chain)
	chain.target_event = target
	chain.enable = true
	chain.execute(null)
	assert_true(target.enabled, "chain event enables its target")
	chain.enable = false
	chain.execute(null)
	assert_false(target.enabled, "chain event disables its target")


# --- ConditionEntityKilled ----------------------------------------------------


func _killed_condition_manager() -> ScenarioTriggerManager:
	var manager := ScenarioTriggerManager.new()
	add_child_autofree(manager)
	assert_push_warning("expected parent to be Scenario")
	return manager


func test_entity_killed_is_false_while_the_entity_stands() -> void:
	var manager := _killed_condition_manager()
	var entity: Actor = FakePieces.unit(FakePieces.PLAIN)
	entity.name = "Watched"
	add_child_autofree(entity)

	var condition := ConditionEntityKilled.new()
	condition.entity_name = "Watched"
	assert_false(condition.evaluate(manager), "the entity is alive and in the world")
	assert_eq(condition.highlight_entities(manager), [entity], "and is marked as the target")


func test_entity_killed_becomes_true_once_the_entity_is_freed() -> void:
	# Regression: the guard used to be `if _entity_ref == null: return false`, and in GDScript
	# a FREED Object compares equal to null — so the reference started reporting itself as
	# null the instant the entity died, and the check could never become true. It only ever
	# passed in the sliver where the node was out of the tree but not yet freed, which
	# queue_free() does not leave open.
	var manager := _killed_condition_manager()
	var entity: Actor = FakePieces.unit(FakePieces.PLAIN)
	entity.name = "Watched"
	add_child(entity)

	var condition := ConditionEntityKilled.new()
	condition.entity_name = "Watched"
	assert_false(condition.evaluate(manager), "resolves while alive")

	entity.get_parent().remove_child(entity)
	entity.free()
	assert_true(condition.evaluate(manager), "destroying the entity satisfies the check")
	assert_eq(condition.highlight_entities(manager), [], "and nothing is left to mark")


func test_entity_killed_fails_closed_on_an_unknown_name() -> void:
	# A typo'd or renamed target must NOT read as "already destroyed" — that would fire the
	# trigger on its first tick. It reports false forever, and warns so the author finds out.
	var manager := _killed_condition_manager()
	var condition := ConditionEntityKilled.new()
	condition.entity_name = "NoSuchNode"

	assert_false(condition.evaluate(manager), "an unresolvable target never satisfies")
	assert_push_warning("no entity named 'NoSuchNode'")
