extends GutTest

## The action side a mission shares with the bot: an authored chain through the actuator, the
## retreat and build policies, and a TacticRule's action as the shared policy it names.
## gdd/systems/scenario-scripting/tactics.md §Trigger-decided mission commanders.

const POST: Vector3 = Vector3(20.0, 0.0, 0.0)
const STRUCTURE: StringName = &"test_outpost"


## Records the verbs a policy uses instead of ordering anything.
class SpyActuator:
	extends BotActuator
	var calls: Array = []
	var builds_allowed: bool = true
	var cover_taken: bool = true

	func _init() -> void:
		super(null)

	func move(a_units: Array, a_world_pos: Vector3) -> void:
		calls.append(["move", a_units.duplicate(), a_world_pos])

	func garrison_into(a_unit: Actor, a_host: Actor) -> bool:
		calls.append(["garrison_into", a_unit, a_host])
		return cover_taken

	func would_build(_a_builder: Actor, _a_type: StringName, _a_world_pos: Vector3) -> bool:
		return builds_allowed

	func build(
		a_builder: Actor, a_type: StringName, a_world_pos: Vector3, _a_quarter_turns: int = 0
	) -> bool:
		calls.append(["build", a_builder, a_type, a_world_pos])
		return true


## A bot whose cover and home are whatever the test says.
class StubBot:
	extends Bot
	var cover: Actor = null
	var home: Vector3 = Vector3(-30.0, 0.0, 0.0)

	func nearest_garrison_for(_a_unit: Actor) -> Actor:
		return cover

	func nearest_own_structure(_a_from: Vector3) -> Actor:
		return null

	func home_centroid() -> Vector3:
		return home


var _act: SpyActuator
var _bot: StubBot


func before_each() -> void:
	_act = SpyActuator.new()
	_bot = StubBot.new()
	add_child_autofree(_bot)


func _unit(a_at: Vector3 = Vector3.ZERO) -> Actor:
	var unit: Actor = FakePieces.unit(FakePieces.SOLDIER)
	add_child_autofree(unit)
	unit.global_position = a_at
	return unit


#region The chain verb
func test_a_chain_is_issued_whole_and_counted() -> void:
	var act := BotActuator.new(null)
	var unit: Actor = _unit()
	var chain: Array[MoveCommand] = [
		MoveCommand.new(CommandMessage.new(null, null, null, POST)),
		MoveCommand.new(CommandMessage.new(null, null, null, Vector3.ZERO)),
	]
	assert_true(act.issue_chain(unit, chain))
	assert_eq(unit.current_command(), chain[0])
	assert_eq(act.usage.actions()["chain"][String(unit.id)][BotUsageLog.OUTCOME_ISSUED], 1)


func test_a_chain_whose_first_order_is_refused_is_not_issued() -> void:
	var act := BotActuator.new(null)
	var unit: Actor = _unit()
	var chain: Array[MoveCommand] = [Occupy.new(CommandMessage.new(null))]
	assert_false(act.issue_chain(unit, chain), "Occupy with no host is refused")
	assert_true(unit.command_receiver.is_idle())


func test_only_the_actuator_in_the_bot_may_issue_a_chain() -> void:
	var dir: String = "res://scripts/interface/commander/"
	for file_name: String in DirAccess.get_files_at(dir):
		if not file_name.ends_with(".gd") or file_name == "bot_actuator.gd":
			continue
		var text: String = FileAccess.get_file_as_string(dir + file_name)
		assert_false(text.contains("issue_chain("), "%s queues orders" % file_name)


#endregion


#region RetreatPolicy
func test_retreat_takes_cover_first() -> void:
	var host: Actor = _unit(Vector3(5.0, 0.0, 0.0))
	_bot.cover = host
	var unit: Actor = _unit()
	RetreatPolicy.new(_bot, _act, POST).issue([unit])
	assert_eq(_act.calls, [["garrison_into", unit, host]])


func test_retreat_walks_to_its_point_when_no_cover_takes_it() -> void:
	var unit: Actor = _unit()
	RetreatPolicy.new(_bot, _act, POST).issue([unit])
	assert_eq(_act.calls, [["move", [unit], POST]])


func test_retreat_without_a_point_walks_home() -> void:
	var unit: Actor = _unit()
	RetreatPolicy.new(_bot, _act).issue([unit])
	assert_eq(_act.calls, [["move", [unit], _bot.home]])


func test_an_arrived_retreat_is_left_standing() -> void:
	var unit: Actor = _unit(POST)
	RetreatPolicy.new(_bot, _act, POST).issue([unit])
	assert_eq(_act.calls, [])


#endregion


#region BuildPolicy
func test_build_orders_the_first_able_member() -> void:
	var a: Actor = _unit()
	var b: Actor = _unit()
	BuildPolicy.new(_act, STRUCTURE, POST).issue([a, b])
	assert_eq(_act.calls, [["build", a, STRUCTURE, POST]], "one builder, not the squad")


func test_build_waits_while_the_site_is_taken() -> void:
	_act.builds_allowed = false
	BuildPolicy.new(_act, STRUCTURE, POST).issue([_unit()])
	assert_eq(_act.calls, [])


#endregion


#region TacticRule → policy
func _rule(a_action: TacticRule.Action, a_with_point: bool) -> TacticRule:
	var rule := TacticRule.new()
	rule.name = "Rule"
	rule.action = a_action
	if a_with_point:
		var marker := Marker3D.new()
		marker.name = "Point"
		marker.position = POST
		rule.add_child(marker)
		rule.point_path = NodePath("Point")
	return rule


func _tactic_on(a_rule: TacticRule, a_commander: Commander) -> ScenarioTactic:
	var manager := ScenarioTriggerManager.new()
	add_child_autofree(manager)
	assert_push_warning("expected parent to be Scenario")
	var tactic := ScenarioTactic.new()
	tactic.unit_group = &"cluster"
	tactic.add_child(a_rule)
	add_child_autofree(tactic)
	tactic.arm(manager)
	tactic._registered_on = a_commander
	return tactic


func test_a_hold_rule_is_a_hold_policy_at_its_point() -> void:
	var rule: TacticRule = _rule(TacticRule.Action.HOLD, true)
	var policy: SquadPolicy = _tactic_on(rule, _bot)._build_policy(rule)
	assert_true(policy is HoldPolicy)
	assert_eq(policy.destination(), POST)


func test_each_action_names_its_shared_policy() -> void:
	var expected: Dictionary = {
		TacticRule.Action.COMMANDS: TacticRulePolicy,
		TacticRule.Action.STAGE: StagePolicy,
		TacticRule.Action.ASSAULT: AssaultPolicy,
		TacticRule.Action.RETREAT: RetreatPolicy,
	}
	for action: TacticRule.Action in expected:
		var rule: TacticRule = _rule(action, true)
		var policy: SquadPolicy = _tactic_on(rule, _bot)._build_policy(rule)
		assert_is(policy, expected[action], TacticRule.Action.find_key(action))


func test_a_build_rule_keeps_its_structure_at_its_point() -> void:
	var rule: TacticRule = _rule(TacticRule.Action.BUILD, true)
	rule.structure_type = STRUCTURE
	var policy := _tactic_on(rule, _bot)._build_policy(rule) as BuildPolicy
	assert_not_null(policy)
	assert_eq(policy.structure_type, STRUCTURE)
	assert_eq(policy.point, POST)


func test_a_rule_missing_its_point_does_nothing_and_says_so() -> void:
	var rule: TacticRule = _rule(TacticRule.Action.HOLD, false)
	assert_null(_tactic_on(rule, _bot)._build_policy(rule))
	assert_push_warning("names no point")
	assert_eq(rule._get_configuration_warnings().size(), 1, "the Scene dock says so too")


func test_an_escort_rule_carries_the_squad_of_the_tactic_it_names() -> void:
	var served := ScenarioTactic.new()
	served.name = "Served"
	add_child_autofree(served)
	var rule: TacticRule = _rule(TacticRule.Action.ESCORT, false)
	var tactic: ScenarioTactic = _tactic_on(rule, _bot)
	rule.escort_of = rule.get_path_to(served)
	var policy := tactic._build_policy(rule) as EscortPolicy
	assert_not_null(policy)
	assert_eq(policy.consumer, served.squad())


func test_a_policy_that_steers_by_bot_senses_needs_a_bot() -> void:
	var commander := Commander.new()
	add_child_autofree(commander)
	var rule: TacticRule = _rule(TacticRule.Action.RETREAT, true)
	assert_null(_tactic_on(rule, commander)._build_policy(rule))
	assert_push_warning("not a Bot")

#endregion
