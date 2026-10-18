extends GutTest

## What an alliance knows of a piece (AlliancePerspective), and the checks that read it: a
## condition's ALLIANCE perspective and EventCommandTarget's. Vision is a band of x rather than a
## Fog, so "out of sight" is a place a piece can be put.
## gdd/systems/scenario-scripting/tactics.md §Trigger-decided mission commanders.

const IN_SIGHT: Vector3 = Vector3(2.0, 0.0, 0.0)
const OUT_OF_SIGHT: Vector3 = Vector3(50.0, 0.0, 0.0)
## Vision covers x below this.
const VISION_X: float = 10.0


## A commander that sees x < VISION_X and nothing else.
class BandCommander:
	extends Commander

	func has_vision_at(a_world_pos: Vector3) -> bool:
		return a_world_pos.x < VISION_X


var _scenario: Scenario
var _manager: ScenarioTriggerManager
## 1 and 2 are allies; 3 is their enemy.
var _one: BandCommander
var _two: BandCommander
var _three: BandCommander


func before_each() -> void:
	_scenario = Scenario.new()
	var neutral := Commander.new()
	neutral.id = 0
	add_child_autofree(neutral)
	_one = _commander(1)
	_two = _commander(2)
	_three = _commander(3)
	var allies: int = (1 << 1) | (1 << 2)
	_one.set_alliance(1, allies)
	_two.set_alliance(1, allies)
	_three.set_alliance(2, 1 << 3)
	_scenario.commanders = [neutral, _one, _two, _three]
	_manager = ScenarioTriggerManager.new()
	add_child_autofree(_manager)
	assert_push_warning("expected parent to be Scenario")
	_manager.scenario = _scenario


func after_each() -> void:
	if _manager != null and _manager.simulation_clock != null:
		_manager.simulation_clock.clear()
	_scenario.free()


func _commander(a_id: int) -> BandCommander:
	var commander := BandCommander.new()
	commander.id = a_id
	add_child_autofree(commander)
	commander.blackboard = CommanderBlackboard.new(commander)
	return commander


func _unit(a_owner: Commander, a_at: Vector3, a_options: Dictionary = FakePieces.SOLDIER) -> Actor:
	var unit: Actor = FakePieces.unit(a_options)
	add_child_autofree(unit)
	unit.commander = a_owner
	unit.add_to_group("unit")
	unit.global_position = a_at
	return unit


#region Positions
func test_a_side_knows_where_its_own_and_its_allies_pieces_stand() -> void:
	var own: Actor = _unit(_one, OUT_OF_SIGHT)
	var ally: Actor = _unit(_two, OUT_OF_SIGHT)
	assert_eq(AlliancePerspective.position_of(_manager, 1, own), OUT_OF_SIGHT)
	assert_eq(AlliancePerspective.position_of(_manager, 1, ally), OUT_OF_SIGHT)


func test_an_enemy_in_sight_is_known_where_it_stands() -> void:
	var enemy: Actor = _unit(_three, IN_SIGHT)
	assert_eq(AlliancePerspective.position_of(_manager, 1, enemy), IN_SIGHT)


func test_an_unseen_unbelieved_enemy_is_unknown() -> void:
	var enemy: Actor = _unit(_three, OUT_OF_SIGHT)
	assert_null(AlliancePerspective.position_of(_manager, 1, enemy))
	assert_false(AlliancePerspective.knows(_manager, 1, enemy))


func test_an_allys_belief_is_the_alliances_at_the_last_known_spot() -> void:
	var enemy: Actor = _unit(_three, IN_SIGHT)
	_two.blackboard._upsert(enemy, 0.0)
	enemy.global_position = OUT_OF_SIGHT
	assert_eq(
		AlliancePerspective.position_of(_manager, 1, enemy),
		IN_SIGHT,
		"commander 1 reads what its ally saw, where it saw it"
	)


func test_a_stealthed_enemy_in_sight_is_unknown() -> void:
	var options: Dictionary = FakePieces.SOLDIER.duplicate()
	options["stealth"] = true
	var enemy: Actor = _unit(_three, IN_SIGHT, options)
	assert_null(AlliancePerspective.position_of(_manager, 1, enemy))


func test_the_alliance_is_every_member() -> void:
	assert_eq(AlliancePerspective.members_of(_manager, 2).size(), 2)
	assert_eq(AlliancePerspective.members_of(_manager, 3).size(), 1)
	assert_eq(AlliancePerspective.members_of(_manager, 0).size(), 0, "neutral is nobody's")


#endregion


#region Conditions
func _enemy_count(a_perspective: Condition.Perspective) -> ConditionUnitCount:
	var condition := ConditionUnitCount.new()
	condition.commander_id = 3
	condition.comparison = ConditionUnitCount.Comparison.AT_LEAST
	condition.count = 2
	condition.perspective = a_perspective
	condition.perspective_commander_id = 1
	return condition


func test_an_omniscient_count_sees_every_unit() -> void:
	_unit(_three, IN_SIGHT)
	_unit(_three, OUT_OF_SIGHT)
	assert_true(_enemy_count(Condition.Perspective.OMNISCIENT).evaluate(_manager))


func test_an_alliance_count_sees_only_what_the_alliance_knows() -> void:
	_unit(_three, IN_SIGHT)
	_unit(_three, OUT_OF_SIGHT)
	assert_false(_enemy_count(Condition.Perspective.ALLIANCE).evaluate(_manager))


func test_an_alliance_group_count_leaves_out_the_unknown() -> void:
	var seen: Actor = _unit(_three, IN_SIGHT)
	var unseen: Actor = _unit(_three, OUT_OF_SIGHT)
	seen.add_to_group(&"wave")
	unseen.add_to_group(&"wave")
	var condition := ConditionGroupCount.new()
	condition.group = &"wave"
	condition.perspective = Condition.Perspective.ALLIANCE
	condition.perspective_commander_id = 1
	assert_eq(condition.matching_nodes(_manager).size(), 1)


func test_a_check_that_cannot_honour_a_perspective_says_so() -> void:
	var timer := ConditionTimer.new()
	assert_eq(timer.perspective_warning(), "", "omniscient is always fine")
	timer.perspective = Condition.Perspective.ALLIANCE
	assert_string_contains(timer.perspective_warning(), "ConditionTimer")
	var count := ConditionUnitCount.new()
	count.perspective = Condition.Perspective.ALLIANCE
	assert_eq(count.perspective_warning(), "", "a check over pieces honours it")


#endregion


#region EventCommandTarget
func test_an_alliance_target_pick_uses_only_believed_positions() -> void:
	var seen: Actor = _unit(_three, IN_SIGHT)
	var remembered: Actor = _unit(_three, IN_SIGHT)
	_one.blackboard._upsert(remembered, 0.0)
	remembered.global_position = OUT_OF_SIGHT
	var unseen: Actor = _unit(_three, OUT_OF_SIGHT)
	var target := EventCommandTarget.new()
	target.perspective = Condition.Perspective.ALLIANCE
	autofree(target)
	var positions: Dictionary = target._known_positions(_manager, 1, [seen, remembered, unseen])
	assert_eq(positions.size(), 2, "the unseen enemy is left out")
	assert_eq(positions[remembered], IN_SIGHT, "the remembered one is where it was seen")
	target.perspective = Condition.Perspective.OMNISCIENT
	positions = target._known_positions(_manager, 1, [seen, remembered, unseen])
	assert_eq(positions.size(), 3)
	assert_eq(positions[remembered], OUT_OF_SIGHT)

#endregion
