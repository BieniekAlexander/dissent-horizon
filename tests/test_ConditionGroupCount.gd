extends GutTest

## Tests for ConditionGroupCount and the EventSpawnEntities.spawn_groups that feeds it —
## labelling one wave of spawns so a later check can talk about exactly those things.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_ConditionGroupCount.gd -gexit

const UNIT: PackedScene = preload("res://scenes/entities/units/an/an_bioLight_builder.tscn")
const GROUP: StringName = &"test_ambush_wave"

var _manager: ScenarioTriggerManager


func before_each() -> void:
	_manager = ScenarioTriggerManager.new()
	add_child_autofree(_manager)
	assert_push_warning("expected parent to be Scenario")


func after_each() -> void:
	if _manager.simulation_clock != null:
		_manager.simulation_clock.clear()
	get_tree().paused = false


## A node in the group under test, live in the tree.
func _member(a_group: StringName = GROUP) -> Node:
	var node := Node.new()
	node.add_to_group(a_group)
	add_child_autofree(node)
	return node


func _condition(a_comparison: int, a_count: int, a_group: StringName = GROUP) -> ConditionGroupCount:
	var condition := ConditionGroupCount.new()
	condition.group = a_group
	condition.comparison = a_comparison
	condition.count = a_count
	return condition


# --- Counting -------------------------------------------------------------------

func test_at_least_counts_up_to_its_threshold() -> void:
	var condition := _condition(ConditionGroupCount.Comparison.AT_LEAST, 2)
	assert_false(condition.evaluate(_manager), "nothing in the group yet")
	_member()
	assert_false(condition.evaluate(_manager), "one is not two")
	_member()
	assert_true(condition.evaluate(_manager), "two is")


func test_at_most_counts_down_to_its_threshold() -> void:
	var a := _member()
	_member()
	var condition := _condition(ConditionGroupCount.Comparison.AT_MOST, 1)
	assert_false(condition.evaluate(_manager), "two left")
	a.get_parent().remove_child(a)
	a.free()
	assert_true(condition.evaluate(_manager), "one left")


func test_exactly_matches_only_that_number() -> void:
	var condition := _condition(ConditionGroupCount.Comparison.EXACTLY, 1)
	_member()
	assert_true(condition.evaluate(_manager))
	_member()
	assert_false(condition.evaluate(_manager), "two is not exactly one")


func test_only_the_named_group_is_counted() -> void:
	_member(&"test_some_other_wave")
	var condition := _condition(ConditionGroupCount.Comparison.AT_LEAST, 1)
	assert_false(condition.evaluate(_manager), "a different label is a different wave")
	_member()
	assert_true(condition.evaluate(_manager))


func test_an_unset_group_never_matches() -> void:
	# Counting zero would make AT_MOST true on the first tick; an un-authored check that fires
	# immediately is worse than one that never does.
	var condition := _condition(ConditionGroupCount.Comparison.AT_MOST, 0, &"")
	assert_false(condition.evaluate(_manager))


func test_a_node_dying_this_frame_is_not_counted() -> void:
	# get_nodes_in_group still returns a queue_freed node until the end of the frame, so a
	# "wipe out the wave" check would otherwise resolve a tick late.
	var doomed := _member()
	var condition := _condition(ConditionGroupCount.Comparison.AT_MOST, 0)
	assert_false(condition.evaluate(_manager), "still standing")
	doomed.queue_free()
	assert_true(condition.evaluate(_manager), "resolves on the tick it dies, not the next")


# --- Highlights -----------------------------------------------------------------

func test_at_most_marks_the_members_that_can_be_marked() -> void:
	var entity: Commandable = UNIT.instantiate()
	entity.add_to_group(GROUP)
	add_child_autofree(entity)
	_member()  # a plain Node in the same group — nothing to point at

	var condition := _condition(ConditionGroupCount.Comparison.AT_MOST, 0)
	var marked: Array[Entity] = condition.highlight_entities(_manager)
	assert_eq(marked, [entity] as Array[Entity], "only the thing with a position in the world")


func test_at_least_marks_nothing() -> void:
	var entity: Commandable = UNIT.instantiate()
	entity.add_to_group(GROUP)
	add_child_autofree(entity)
	var condition := _condition(ConditionGroupCount.Comparison.AT_LEAST, 3)
	assert_eq(condition.highlight_entities(_manager), [], "waiting on things that don't exist")


# --- EventSpawnEntities.spawn_groups --------------------------------------------

func test_spawn_groups_label_everything_the_event_produced() -> void:
	var event := EventSpawnEntities.new()
	event.spawn_groups = [GROUP, &"test_second_label"] as Array[StringName]
	add_child_autofree(event)

	var spawned: Commandable = UNIT.instantiate()
	event._apply_spawn_groups(spawned)
	autofree(spawned)

	assert_true(spawned.is_in_group(GROUP), "the wave's label")
	assert_true(spawned.is_in_group(&"test_second_label"), "and any others")


func test_blank_group_rows_are_skipped() -> void:
	# An Array export shows a blank row whenever you grow it in the inspector; joining the ""
	# group would pollute every check that forgets to set its own name.
	var event := EventSpawnEntities.new()
	event.spawn_groups = [&"", GROUP] as Array[StringName]
	add_child_autofree(event)

	var spawned := Node.new()
	event._apply_spawn_groups(spawned)
	autofree(spawned)

	assert_false(spawned.is_in_group(&""), "no empty-name membership")
	assert_true(spawned.is_in_group(GROUP))


func test_an_event_with_no_groups_labels_nothing() -> void:
	var event := EventSpawnEntities.new()
	add_child_autofree(event)
	var spawned := Node.new()
	event._apply_spawn_groups(spawned)
	autofree(spawned)
	assert_eq(spawned.get_groups().size(), 0, "the default is no labelling at all")
