extends GutTest

## Sub-steps (a trigger's own GlobalTrigger children, reached in order) and `resolves_earlier`
## (reaching a later step completes every ancestor first). See
## gdd/systems/scenario-scripting/objectives-and-completion.md §Sub-steps.


## A condition the test flips by hand, announcing the change the way a push condition would.
class StubCondition:
	extends Condition
	var result: bool = false

	func evaluate(_a_manager: ScenarioTriggerManager) -> bool:
		return result

	func satisfy() -> void:
		result = true
		_last = true
		state_changed.emit()


## Writes its trigger's name into a shared log when run, so a test can read the firing order.
class LogEvent:
	extends AbstractEvent
	var log: Array

	func execute(_a_manager: ScenarioTriggerManager) -> void:
		log.append(String(get_parent().name))


var _manager: ScenarioTriggerManager
var _triggers: Dictionary = {}
var _conditions: Dictionary = {}
var _log: Array = []


func before_each() -> void:
	_manager = ScenarioTriggerManager.new()
	_triggers = {}
	_conditions = {}
	_log = []


func after_each() -> void:
	if _manager.simulation_clock != null:
		_manager.simulation_clock.clear()
	get_tree().paused = false
	if not _manager.is_inside_tree():
		_manager.free()


## A trigger named `a_name` under `a_parent` (the manager when null), depending on the named
## triggers. `a_has_condition` false leaves it conditionless, as a trigger with sub-steps is.
func _add(
	a_name: String, a_parent: Node = null, a_prerequisites: Array = [], a_has_condition: bool = true
) -> GlobalTrigger:
	var trigger := GlobalTrigger.new()
	trigger.name = a_name
	if a_has_condition:
		var condition := StubCondition.new()
		trigger.conditions = [condition]
		_conditions[a_name] = condition
	var edges: Array[GlobalTrigger] = []
	for dependency: String in a_prerequisites:
		edges.append(_triggers[dependency])
	trigger.prerequisites = edges
	var event := LogEvent.new()
	event.log = _log
	trigger.add_child(event)
	(a_parent if a_parent != null else _manager).add_child(trigger)
	_triggers[a_name] = trigger
	return trigger


## An objective walked as three waypoints.
func _waypoints(a_name: String, a_prerequisites: Array = []) -> GlobalTrigger:
	var objective: GlobalTrigger = _add(a_name, null, a_prerequisites, false)
	for i: int in 3:
		_add("%s_W%d" % [a_name, i + 1], objective)
	return objective


## Put the manager in the tree; with no Map its _ready arms the triggers at once.
func _start() -> void:
	add_child_autofree(_manager)
	assert_push_warning("expected parent to be Scenario")


func _reach(a_name: String) -> void:
	(_conditions[a_name] as StubCondition).satisfy()


func _trigger(a_name: String) -> GlobalTrigger:
	return _triggers[a_name]


# --- Sub-steps -----------------------------------------------------------------


func test_sub_steps_are_collected_with_their_trigger() -> void:
	_waypoints("Go")
	_start()
	assert_eq(_manager.global_triggers.size(), 4)


func test_only_the_first_waypoint_is_current() -> void:
	_waypoints("Go")
	_start()
	assert_true(_trigger("Go_W1").enabled, "current")
	assert_false(_trigger("Go_W2").enabled, "not shown yet")
	assert_true(_trigger("Go_W2").is_watching(), "but watched")
	assert_false(_trigger("Go").has_fired, "a trigger with sub-steps does not fire on its own")


func test_reaching_each_waypoint_in_turn_completes_the_objective() -> void:
	_waypoints("Go")
	_start()
	_reach("Go_W1")
	assert_true(_trigger("Go_W2").enabled, "the next is current")
	_reach("Go_W2")
	_reach("Go_W3")
	assert_eq(_log, ["Go_W1", "Go_W2", "Go_W3", "Go"])
	assert_true(_trigger("Go").has_fired)


func test_reaching_a_later_waypoint_completes_the_earlier_ones_in_order() -> void:
	_waypoints("Go")
	_start()
	_reach("Go_W3")
	assert_eq(_log, ["Go_W1", "Go_W2", "Go_W3", "Go"], "every skipped step's events still run")


func test_waypoints_wait_for_their_objective() -> void:
	_add("First")
	_waypoints("Go", ["First"])
	_start()
	assert_false(_trigger("Go_W1").is_watching(), "the objective is not current yet")
	_reach("First")
	assert_true(_trigger("Go_W1").enabled)


# --- resolves_earlier ----------------------------------------------------------


func test_a_flagged_trigger_watches_unseen_from_the_start() -> void:
	_add("First")
	var later: GlobalTrigger = _add("Later", null, ["First"])
	later.resolves_earlier = true
	_start()
	assert_false(later.enabled, "not current, so not shown")
	assert_true(later.is_watching())


func test_a_flagged_trigger_completes_every_ancestor_first() -> void:
	_add("A")
	_add("B", null, ["A"])
	var c: GlobalTrigger = _add("C", null, ["B"])
	c.resolves_earlier = true
	_start()
	_reach("C")
	assert_eq(_log, ["A", "B", "C"])


func test_an_ancestor_with_waypoints_completes_them_first() -> void:
	_waypoints("Go")
	var later: GlobalTrigger = _add("Later", null, ["Go"])
	later.resolves_earlier = true
	_start()
	_reach("Later")
	assert_eq(_log, ["Go_W1", "Go_W2", "Go_W3", "Go", "Later"])


func test_without_the_flag_a_later_trigger_does_not_watch() -> void:
	_add("First")
	_add("Later", null, ["First"])
	_start()
	assert_false(_trigger("Later").is_watching())


func test_a_waypoint_of_a_flagged_objective_resolves_the_objectives_before_it() -> void:
	_add("First")
	var go: GlobalTrigger = _waypoints("Go", ["First"])
	go.resolves_earlier = true
	_start()
	assert_true(_trigger("Go_W2").is_watching(), "watched while the objective watches early")
	assert_false(_trigger("Go_W1").enabled, "but none is current")
	_reach("Go_W2")
	assert_eq(_log, ["First", "Go_W1", "Go_W2"])
	assert_true(_trigger("Go_W3").enabled, "the objective is current now, and so is W3")
