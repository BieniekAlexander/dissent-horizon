extends GutTest

## EventShareVision: a commander starts or stops lending its vision to its allies mid-mission.

var _scenario: Scenario
var _manager: ScenarioTriggerManager
## 1 and 2 are allies.
var _one: Commander
var _two: Commander


func before_each() -> void:
	_scenario = Scenario.new()
	_one = _commander(1)
	_two = _commander(2)
	var allies: int = (1 << 1) | (1 << 2)
	_one.set_alliance(1, allies)
	_two.set_alliance(1, allies)
	_scenario.commanders = [_one, _two]
	_manager = ScenarioTriggerManager.new()
	add_child_autofree(_manager)
	assert_push_warning("expected parent to be Scenario")
	_manager.scenario = _scenario


func after_each() -> void:
	if _manager != null and _manager.simulation_clock != null:
		_manager.simulation_clock.clear()
	_scenario.free()


func _commander(a_id: int) -> Commander:
	var commander := Commander.new()
	commander.id = a_id
	add_child_autofree(commander)
	return commander


func _event(a_shares: bool) -> EventShareVision:
	var event := EventShareVision.new()
	event.commander_id = 2
	event.shares_vision = a_shares
	add_child_autofree(event)
	return event


func test_a_withheld_vision_is_lent_once_shared() -> void:
	_two.shares_vision_with_allies = false
	assert_false(_two.lends_vision_to(1), "withheld at the start")
	_event(true).execute(_manager)
	assert_true(_two.lends_vision_to(1), "lent from now on")


func test_a_lent_vision_can_be_withheld() -> void:
	_event(false).execute(_manager)
	assert_false(_two.lends_vision_to(1))
	assert_true(_two.lends_vision_to(2), "a commander always sees its own")


func test_an_unknown_commander_is_reported() -> void:
	var event: EventShareVision = _event(true)
	event.commander_id = 9
	event.execute(_manager)
	assert_push_error("no commander 9")
