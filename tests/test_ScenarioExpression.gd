extends GutTest

## Tests for authored numeric expressions in scenario fields, and the two fields that take
## them (ConditionTimer.seconds_expression, EventSpawnEntities.count_expression), plus the
## randomized spawn anchor.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_ScenarioExpression.gd -gexit

var _scenario: Scenario
var _manager: ScenarioTriggerManager


func before_each() -> void:
	_scenario = Scenario.new()
	_scenario.tick = 0
	_manager = ScenarioTriggerManager.new()
	add_child_autofree(_manager)
	assert_push_warning("expected parent to be Scenario")
	_manager.scenario = _scenario


func after_each() -> void:
	if _manager != null and _manager.simulation_clock != null:
		_manager.simulation_clock.clear()
	if _scenario != null:
		_scenario.free()
	get_tree().paused = false


# --- ScenarioExpression ---------------------------------------------------------

func test_plain_arithmetic() -> void:
	assert_eq(ScenarioExpression.evaluate_float("1 + 2 * 3", 0.0, _manager), 7.0)
	assert_eq(ScenarioExpression.evaluate_int("10 / 4.0", 0, _manager), 3, "rounds, not truncates")


func test_builtin_functions_are_available() -> void:
	# The whole reason for using Godot's Expression rather than hand-rolling a parser.
	assert_eq(ScenarioExpression.evaluate_float("max(3, 7)", 0.0, _manager), 7.0)
	assert_eq(ScenarioExpression.evaluate_float("clamp(15, 0, 10)", 0.0, _manager), 10.0)
	var roll: int = ScenarioExpression.evaluate_int("randi_range(2, 4)", 0, _manager)
	assert_between(roll, 2, 4, "randi_range works inside an expression")


func test_tick_and_seconds_inputs() -> void:
	_scenario.tick = 90
	assert_eq(ScenarioExpression.evaluate_float("tick", 0.0, _manager), 90.0)
	assert_eq(ScenarioExpression.evaluate_float("seconds", 0.0, _manager), 3.0,
		"90 ticks at 30 ticks/second is 3 seconds")


func test_fires_input() -> void:
	assert_eq(ScenarioExpression.evaluate_int("2 + fires", 0, _manager, 0), 2, "first cycle")
	assert_eq(ScenarioExpression.evaluate_int("2 + fires", 0, _manager, 3), 5, "fourth cycle")


func test_a_blank_expression_uses_the_fallback() -> void:
	assert_eq(ScenarioExpression.evaluate_float("", 42.0, _manager), 42.0)
	assert_eq(ScenarioExpression.evaluate_float("   ", 42.0, _manager), 42.0, "whitespace too")
	assert_false(ScenarioExpression.is_authored("  "))


func test_unparseable_expression_falls_back_and_warns() -> void:
	# A typo must degrade the scenario to its authored constant, not break the mission.
	# NOTE: each bad source below is unique, because a failed parse is CACHED — the same
	# text warns once per process, so reusing "1 +" here would leave a later test with no
	# warning to expect.
	assert_eq(ScenarioExpression.evaluate_float("1 +", 9.0, _manager), 9.0)
	assert_push_warning("could not parse")


func test_unknown_identifier_falls_back() -> void:
	# Only INPUT_NAMES exist; anything else fails at execute rather than reading zero.
	assert_eq(ScenarioExpression.evaluate_float("wave_number * 2", 7.0, _manager), 7.0)
	assert_push_warning("could not evaluate")


func test_engine_singletons_are_not_reachable() -> void:
	# Documented limitation of Expression itself — `tick` is the supported substitute.
	assert_eq(ScenarioExpression.evaluate_float("Engine.get_physics_frames()", 4.0, _manager), 4.0)
	assert_push_warning("could not evaluate")


func test_non_numeric_result_falls_back() -> void:
	assert_eq(ScenarioExpression.evaluate_float("\"hello\"", 5.0, _manager), 5.0)
	assert_push_warning("not a number")


# --- ConditionTimer.seconds_expression ------------------------------------------

func _countdown(a_expression: String) -> ConditionTimer:
	var condition := ConditionTimer.new()
	condition.mode = ConditionTimer.Mode.COUNTDOWN
	condition.seconds_expression = a_expression
	return condition


func test_a_plain_number_is_a_valid_interval() -> void:
	# The reason there is no separate numeric field: "2" is already an expression.
	var condition := _countdown("2")
	_scenario.tick = 0
	assert_false(condition.evaluate(_manager), "countdown just started")
	_scenario.tick = TimeUtils.ticks_from_seconds(2.0)
	assert_true(condition.evaluate(_manager))


func test_a_blank_interval_means_the_default() -> void:
	var condition := _countdown("")
	_scenario.tick = 0
	condition.evaluate(_manager)
	assert_eq(condition._target_ticks,
		TimeUtils.ticks_from_seconds(ConditionTimer.DEFAULT_SECONDS))


func test_countdown_resolves_its_interval_once_per_cycle() -> void:
	# The load-bearing part: a random interval must be drawn ONCE and counted down to. If it
	# were re-evaluated per frame the deadline would jitter every tick and never land.
	var condition := _countdown("randi_range(1, 40)")
	_scenario.tick = 0
	condition.evaluate(_manager)
	var first: int = condition._target_ticks
	for f: int in range(1, 10):
		_scenario.tick = f
		condition.evaluate(_manager)
	assert_eq(condition._target_ticks, first, "the interval is stable across frames")


func test_reset_rerolls_the_interval_for_the_next_cycle() -> void:
	var condition := _countdown("5")
	_scenario.tick = 0
	condition.evaluate(_manager)
	assert_eq(condition._target_ticks, TimeUtils.ticks_from_seconds(5.0))
	condition.reset()
	assert_eq(condition._target_ticks, -1, "a repeating trigger re-rolls next cycle")


func test_a_bad_expression_falls_back_to_the_default() -> void:
	var condition := _countdown("2 *")  # distinct source: parse failures are cached
	_scenario.tick = 0
	condition.evaluate(_manager)
	assert_push_warning("could not parse")
	assert_eq(condition._target_ticks,
		TimeUtils.ticks_from_seconds(ConditionTimer.DEFAULT_SECONDS),
		"a typo degrades to the default, it does not break the mission")


func test_legacy_seconds_property_migrates_to_the_expression() -> void:
	# Sub-resources authored before this change store `seconds = 15.0`; PackedScene applies
	# stored properties through set(), which routes the now-removed name to _set.
	var condition := ConditionTimer.new()
	condition.set("seconds", 15.0)
	assert_eq(float(condition.seconds_expression), 15.0)


func test_an_authored_expression_survives_a_legacy_seconds_value() -> void:
	var condition := ConditionTimer.new()
	condition.seconds_expression = "7"
	condition.set("seconds", 15.0)
	assert_eq(condition.seconds_expression, "7", "the authored expression wins either order")


# --- fire_count -----------------------------------------------------------------

func test_fire_count_counts_cycles() -> void:
	var trigger := GlobalTrigger.new()
	trigger.one_shot = false
	var condition := ConditionTimer.new()  # ELAPSED_SINCE_START, 0s -> immediately true
	condition.seconds_expression = "0"
	trigger.conditions = [condition]
	_manager.add_child(trigger)

	assert_eq(trigger.fire_count, 0, "nothing has fired yet")
	trigger.fire(_manager)
	assert_eq(trigger.fire_count, 1)
	trigger.fire(_manager)
	assert_eq(trigger.fire_count, 2)


func test_arming_binds_the_trigger_to_its_conditions() -> void:
	var trigger := GlobalTrigger.new()
	var condition := ConditionTimer.new()
	condition.seconds_expression = "0"
	trigger.conditions = [condition]
	_manager.add_child(trigger)
	trigger.arm(_manager)

	trigger.fire(_manager)
	assert_eq(condition.owner_fire_count(), 1, "the condition can read its trigger's cycles")


func test_an_unowned_condition_reports_zero_fires() -> void:
	var condition := ConditionTimer.new()
	assert_eq(condition.owner_fire_count(), 0, "no trigger bound")


# --- EventSpawnEntities.count_expression ----------------------------------------

func _spawner() -> EventSpawnEntities:
	var event := EventSpawnEntities.new()
	add_child_autofree(event)
	return event


func test_a_blank_count_means_the_default() -> void:
	assert_eq(_spawner().resolve_count(), EventSpawnEntities.DEFAULT_COUNT)


func test_a_plain_number_is_a_valid_count() -> void:
	var event := _spawner()
	event.count_expression = "7"
	assert_eq(event.resolve_count(), 7)


func test_legacy_count_property_migrates_to_the_expression() -> void:
	var event := _spawner()
	event.set("count", 4)  # what an old scene stores
	assert_eq(event.count_expression, "4")
	assert_eq(event.resolve_count(), 4, "the wave size survives the field being replaced")


func test_an_authored_count_expression_survives_a_legacy_value() -> void:
	var event := _spawner()
	event.count_expression = "7"
	event.set("count", 4)
	assert_eq(event.resolve_count(), 7, "the authored expression wins either order")


func test_a_legacy_authored_scene_still_spawns_its_wave() -> void:
	# End-to-end proof the migration is lossless: this scene on disk still says "count = 3"
	# and has never been re-saved. If _set didn't catch it, this would silently read as 1.
	var scene: PackedScene = load("res://scenes/scenario_events/spawn_irregulars.tscn")
	assert_not_null(scene, "the legacy fixture scene loads")
	var event := scene.instantiate() as EventSpawnEntities
	autofree(event)
	assert_not_null(event)
	assert_eq(event.resolve_count(), 3, "count = 3 authored in the .tscn is preserved")


func test_count_is_never_negative() -> void:
	var event := _spawner()
	event.count_expression = "3 - 10"
	assert_eq(event.resolve_count(), 0, "a negative count would silently spawn nothing")


func test_count_grows_with_the_trigger_fire_count() -> void:
	# The motivating case: a repeating wave that gets bigger each time.
	var trigger := GlobalTrigger.new()
	trigger.one_shot = false
	var condition := ConditionTimer.new()
	condition.seconds_expression = "0"
	trigger.conditions = [condition]
	_manager.add_child(trigger)

	var event := EventSpawnEntities.new()
	event.count_expression = "2 + fires"
	trigger.add_child(event)

	assert_eq(event.resolve_count(), 2, "first wave")
	trigger.fire(_manager)
	assert_eq(event.resolve_count(), 3, "second wave")
	trigger.fire(_manager)
	assert_eq(event.resolve_count(), 4, "third wave")


func test_a_nested_event_finds_the_trigger_above_its_parent_event() -> void:
	var trigger := GlobalTrigger.new()
	_manager.add_child(trigger)
	var outer := EventSpawnEntities.new()
	trigger.add_child(outer)
	var inner := EventSpawnEntities.new()
	outer.add_child(inner)

	assert_eq(inner.owning_trigger(), trigger, "walks past the parent event to the trigger")
	assert_eq(inner.owning_manager(), _manager)


# --- Randomized spawn anchor ----------------------------------------------------

func _marker(a_at: Vector3) -> Node3D:
	var node := Node3D.new()
	node.position = a_at
	return node


func test_no_spawn_position_uses_the_events_own_position() -> void:
	var event := _spawner()
	event.position = Vector3(1.0, 2.0, 3.0)
	assert_eq(event.resolve_spawn_anchor(), Vector3(1.0, 2.0, 3.0))


func test_a_childless_spawn_position_is_used_directly() -> void:
	var event := _spawner()
	var marker := _marker(Vector3(5.0, 0.0, 5.0))
	add_child_autofree(marker)
	event.spawn_position = marker
	assert_eq(event.resolve_spawn_anchor(), Vector3(5.0, 0.0, 5.0))


func test_children_are_chosen_at_random() -> void:
	var event := _spawner()
	var parent := Node3D.new()
	add_child_autofree(parent)
	var expected: Array[Vector3] = [
		Vector3(10.0, 0.0, 0.0), Vector3(0.0, 0.0, 10.0), Vector3(-10.0, 0.0, 0.0)
	]
	for at: Vector3 in expected:
		parent.add_child(_marker(at))
	event.spawn_position = parent

	var seen: Dictionary = {}
	for _i: int in 60:
		var anchor: Vector3 = event.resolve_spawn_anchor()
		assert_true(expected.has(anchor), "always lands on one of the markers, got %s" % anchor)
		seen[anchor] = true
	assert_eq(seen.size(), 3, "60 draws across 3 markers should reach all of them")


func test_non_node3d_children_are_skipped() -> void:
	# A plain Node under the marker must not win the draw and spawn the wave at the origin.
	var event := _spawner()
	var parent := Node3D.new()
	parent.position = Vector3(3.0, 0.0, 3.0)
	add_child_autofree(parent)
	parent.add_child(Node.new())
	parent.add_child(_marker(Vector3(9.0, 0.0, 9.0)))
	event.spawn_position = parent

	# The marker's position is LOCAL, so the anchor is the parent's (3,0,3) plus the
	# child's (9,0,9) — the anchor must be a global position, not a local one.
	for _i: int in 20:
		assert_eq(event.resolve_spawn_anchor(), Vector3(12.0, 0.0, 12.0),
			"only the Node3D child is a candidate, resolved globally")


func test_a_spawn_position_with_only_non_node3d_children_uses_itself() -> void:
	var event := _spawner()
	var parent := Node3D.new()
	parent.position = Vector3(4.0, 0.0, 4.0)
	add_child_autofree(parent)
	parent.add_child(Node.new())
	event.spawn_position = parent

	assert_eq(event.resolve_spawn_anchor(), Vector3(4.0, 0.0, 4.0),
		"no usable children, so the node itself is the anchor")


# --- Editor-time validation -----------------------------------------------------

func test_a_good_expression_has_no_validation_error() -> void:
	assert_eq(ScenarioExpression.validation_error("1 + fires"), "")
	assert_eq(ScenarioExpression.validation_error(""), "", "blank is fine — it means the default")


func test_a_misnamed_variable_is_reported_with_the_available_names() -> void:
	# The exact mistake that reached the author as "it always spawns 1": `triggers` is not a
	# variable, so evaluation fails and the count silently falls back to DEFAULT_COUNT.
	var problem: String = ScenarioExpression.validation_error("1 + triggers")
	assert_string_contains(problem, "cannot be evaluated")
	assert_string_contains(problem, "fires", "the message names what IS available")


func test_unparseable_and_non_numeric_are_reported() -> void:
	assert_string_contains(ScenarioExpression.validation_error("1 +"), "cannot be parsed")
	assert_string_contains(ScenarioExpression.validation_error("\"text\""), "not a number")


func test_a_spawn_event_warns_in_the_scene_dock() -> void:
	var event := _spawner()
	event.count_expression = "1 + triggers"
	var warnings: PackedStringArray = event._get_configuration_warnings()
	assert_eq(warnings.size(), 1, "the bad expression is flagged on the node")
	assert_string_contains(warnings[0], "Count Expression")

	event.count_expression = "1 + fires"
	assert_eq(event._get_configuration_warnings().size(), 0, "fixing it clears the warning")


func test_a_trigger_surfaces_its_conditions_warnings() -> void:
	# A Condition is a Resource with no Scene dock entry, so its owning trigger reports for it.
	var trigger := GlobalTrigger.new()
	autofree(trigger)
	var condition := ConditionTimer.new()
	condition.seconds_expression = "10 + waves"
	trigger.conditions = [condition]

	var warnings: PackedStringArray = trigger._get_configuration_warnings()
	assert_eq(warnings.size(), 1)
	assert_string_contains(warnings[0], "Seconds Expression")


func test_a_trigger_with_healthy_conditions_is_quiet() -> void:
	var trigger := GlobalTrigger.new()
	autofree(trigger)
	var condition := ConditionTimer.new()
	condition.seconds_expression = "10 + fires"
	trigger.conditions = [condition]
	assert_eq(trigger._get_configuration_warnings().size(), 0)
