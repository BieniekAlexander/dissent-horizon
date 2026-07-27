extends GutTest

## Tests for the objective DAG: GlobalTrigger.prerequisites gating when a trigger arms, and
## the manager walking the graph forward as triggers fire.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_TriggerPrerequisites.gd -gexit


## A condition the test flips by hand, announcing the change the way a push condition would.
class StubCondition extends Condition:
	var result: bool = false

	func evaluate(_a_manager: ScenarioTriggerManager) -> bool:
		return result

	func satisfy() -> void:
		result = true
		_last = true
		state_changed.emit()


var _manager: ScenarioTriggerManager
## Every trigger built by _add(), by name, so tests read as graph shapes.
var _triggers: Dictionary = {}
var _conditions: Dictionary = {}


func before_each() -> void:
	_manager = ScenarioTriggerManager.new()
	_triggers = {}
	_conditions = {}


func after_each() -> void:
	if _manager.simulation_clock != null:
		_manager.simulation_clock.clear()
	get_tree().paused = false
	if not _manager.is_inside_tree():
		_manager.free()


## Add a trigger named `name`, depending on the named triggers in `prerequisites`.
func _add(a_name: String, a_prerequisites: Array = [], a_mode: int = GlobalTrigger.PrerequisiteMode.ALL_OF) -> GlobalTrigger:
	var trigger := GlobalTrigger.new()
	trigger.name = a_name
	trigger.prerequisite_mode = a_mode
	var condition := StubCondition.new()
	trigger.conditions = [condition]
	var edges: Array[GlobalTrigger] = []
	for dependency: String in a_prerequisites:
		edges.append(_triggers[dependency])
	trigger.prerequisites = edges
	_manager.add_child(trigger)
	_triggers[a_name] = trigger
	_conditions[a_name] = condition
	return trigger


## Put the manager in the tree and arm, skipping the navmesh await (there is no Map here).
func _start() -> void:
	add_child_autofree(_manager)
	assert_push_warning("expected parent to be Scenario")
	_manager._arm_triggers()


func _fire(a_name: String) -> void:
	(_conditions[a_name] as StubCondition).satisfy()


func _armed(a_name: String) -> bool:
	return (_triggers[a_name] as GlobalTrigger).enabled


# --- Gating --------------------------------------------------------------------

func test_a_trigger_with_no_prerequisites_arms_at_the_start() -> void:
	_add("Root")
	_start()
	assert_true(_armed("Root"))


func test_a_gated_trigger_waits_on_its_dependency_alone() -> void:
	# Being gated IS the reason it stays out of the opening round — there is no second "start
	# switched off" flag to remember, and nothing to keep in sync with the edges.
	_add("A")
	_add("B", ["A"])
	_start()
	assert_false(_armed("B"))


func test_completing_a_prerequisite_arms_its_dependent() -> void:
	_add("A")
	_add("B", ["A"])
	_start()
	_fire("A")
	assert_true(_armed("B"), "the DAG advances when A fires")


func test_a_chain_advances_one_step_at_a_time() -> void:
	_add("A")
	_add("B", ["A"])
	_add("C", ["B"])
	_start()
	assert_true(_armed("A"))
	assert_false(_armed("C"))
	_fire("A")
	assert_true(_armed("B"))
	assert_false(_armed("C"), "B firing is what unlocks C, not A")
	_fire("B")
	assert_true(_armed("C"))


# --- Graph shapes ---------------------------------------------------------------

func test_all_of_waits_for_every_prerequisite() -> void:
	# A join: C needs both branches done.
	_add("A")
	_add("B")
	_add("C", ["A", "B"])
	_start()
	_fire("A")
	assert_false(_armed("C"), "one branch isn't enough for ALL_OF")
	_fire("B")
	assert_true(_armed("C"))


func test_any_of_takes_the_first_route_in() -> void:
	_add("A")
	_add("B")
	_add("C", ["A", "B"], GlobalTrigger.PrerequisiteMode.ANY_OF)
	_start()
	_fire("A")
	assert_true(_armed("C"), "reaching it by either route unlocks it")


func test_one_prerequisite_can_fan_out_to_several() -> void:
	_add("A")
	_add("B", ["A"])
	_add("C", ["A"])
	_start()
	_fire("A")
	assert_true(_armed("B"))
	assert_true(_armed("C"))


func test_a_null_row_does_not_wedge_the_mission() -> void:
	# Growing an Array export in the inspector leaves a blank row; a half-filled edge
	# shouldn't stop the scenario dead.
	_add("A")
	var b := _add("B", ["A"])
	b.prerequisites.append(null)
	_start()
	_fire("A")
	assert_true(_armed("B"))


# --- Interaction with the other gates -------------------------------------------

func test_an_imperatively_disabled_trigger_is_not_silently_re_armed() -> void:
	# An ungated trigger switched OFF by an EventChainTrigger has nothing outstanding, so the
	# DAG walk must leave it alone — otherwise the next fire anywhere in the scenario would
	# quietly switch it back on. This is what the has_prerequisites() guard protects.
	_add("A")
	var b := _add("B")
	_start()
	assert_true(_armed("B"), "ungated, so it starts armed")
	b.set_active(false, _manager)
	assert_false(_armed("B"))
	_fire("A")
	assert_false(_armed("B"), "an unrelated trigger firing must not switch it back on")


func test_an_event_chain_trigger_still_overrides_unmet_prerequisites() -> void:
	# An explicit flip is imperative; vetoing it would make the two mechanisms fight.
	_add("A")
	var b := _add("B", ["A"])
	_start()
	var chain := EventChainTrigger.new()
	chain.target_event = b
	chain.enable = true
	_manager.add_child(chain)
	_manager.run_event(chain, null)
	assert_true(_armed("B"), "the override wins over the unmet dependency")


func test_a_fired_trigger_is_not_re_armed() -> void:
	_add("A")
	_add("B", ["A"])
	_start()
	_fire("A")
	_fire("B")
	assert_false(_armed("B"), "one-shot stays done")
	assert_true((_triggers["B"] as GlobalTrigger).has_fired)


# --- Cycles ---------------------------------------------------------------------

func test_a_cycle_is_reported() -> void:
	# Nothing else would notice: every trigger in the loop waits on another, so the mission
	# stalls with an empty log.
	_add("A")
	var b := _add("B", ["A"])
	(_triggers["A"] as GlobalTrigger).prerequisites = [b] as Array[GlobalTrigger]
	_start()
	assert_push_error("prerequisite cycle")
	assert_false(_armed("A"), "and neither end of the loop arms")
	assert_false(_armed("B"))


func test_a_trigger_depending_on_itself_is_reported() -> void:
	var a := _add("A")
	a.prerequisites = [a] as Array[GlobalTrigger]
	_start()
	assert_push_error("prerequisite cycle")


func test_a_diamond_is_not_a_cycle() -> void:
	# Two routes reaching the same node is the shape a DAG is FOR; it must not trip the
	# detector just because the walk reaches D twice.
	_add("A")
	_add("B", ["A"])
	_add("C", ["A"])
	_add("D", ["B", "C"])
	_start()
	_fire("A")
	_fire("B")
	_fire("C")
	assert_true(_armed("D"), "the join opens once both branches are done")
