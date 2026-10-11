extends GutTest

## Tests for ScenarioTactic / TacticRule — the hand-authored "tactics grammar" for one
## cluster of scenario-spawned units (gdd/systems/scenario-scripting/tactics.md).
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_ScenarioTactic.gd -gexit
##
## Exercises only the ScenarioTactic/TacticRule orchestration (rule selection, reissue
## gating) via a spy TacticRule subclass that records what it would have issued rather than
## actually building a command chain — the EventCommand chain-building itself (nav queries,
## formation offsets) is EventIssueCommand's existing, separately-owned behaviour and needs
## no Map/navmesh fixture here.

const UNIT: Dictionary = FakePieces.BUILDER
const GROUP: StringName = &"test_tactic_cluster"


## A condition whose result is set directly by the test — same idiom as test_Triggers.gd.
class StubCondition:
	extends Condition
	var result: bool = false

	func evaluate(_a_manager: ScenarioTriggerManager) -> bool:
		return result


## Records every issue_commands_to() call instead of building a real command chain.
class SpyTacticRule:
	extends TacticRule
	var issued_calls: Array[Dictionary] = []

	func issue_commands_to(
		a_units: Array[Actor],
		_a_manager: ScenarioTriggerManager,
		a_p_commander_id_context: int = -1
	) -> void:
		issued_calls.append(
			{"units": a_units.duplicate(), "commander_id": a_p_commander_id_context}
		)


var _manager: ScenarioTriggerManager


func before_each() -> void:
	_manager = ScenarioTriggerManager.new()
	add_child_autofree(_manager)
	assert_push_warning("expected parent to be Scenario")


func after_each() -> void:
	if _manager.simulation_clock != null:
		_manager.simulation_clock.clear()


func _member(a_group: StringName = GROUP) -> Actor:
	var unit: Actor = FakePieces.make(UNIT)
	unit.add_to_group(a_group)
	add_child_autofree(unit)
	return unit


func _tactic(a_unit_group: StringName, a_rules: Array[TacticRule]) -> ScenarioTactic:
	var tactic := ScenarioTactic.new()
	tactic.unit_group = a_unit_group
	for rule: TacticRule in a_rules:
		tactic.add_child(rule)
	add_child_autofree(tactic)
	tactic.arm(_manager)
	return tactic


# --- No-op guards -------------------------------------------------------------


func test_empty_unit_group_never_issues() -> void:
	var fallback := SpyTacticRule.new()
	var tactic := _tactic(&"", [fallback])
	_member()  # in GROUP, but the tactic isn't watching any group at all
	tactic._physics_process(0.0)
	assert_eq(fallback.issued_calls.size(), 0, "an unset unit_group watches nothing")


func test_no_members_never_issues() -> void:
	var fallback := SpyTacticRule.new()
	var tactic := _tactic(GROUP, [fallback])
	tactic._physics_process(0.0)
	assert_eq(fallback.issued_calls.size(), 0, "nothing spawned into the cluster yet")


func test_no_matching_rule_does_nothing() -> void:
	var gated := SpyTacticRule.new()
	gated.condition = StubCondition.new()  # false by default, and no fallback rule behind it
	var tactic := _tactic(GROUP, [gated])
	_member()
	tactic._physics_process(0.0)
	assert_eq(gated.issued_calls.size(), 0, "the one rule's condition never held")


# --- Rule selection -------------------------------------------------------------


func test_unconditional_rule_is_a_fallback_when_nothing_else_matches() -> void:
	var gated := SpyTacticRule.new()
	gated.condition = StubCondition.new()  # false
	var fallback := SpyTacticRule.new()  # no condition at all
	var tactic := _tactic(GROUP, [gated, fallback])
	var member := _member()
	tactic._think()
	assert_eq(gated.issued_calls.size(), 0, "its condition never held")
	assert_eq(fallback.issued_calls.size(), 1, "the unconditional rule caught it instead")
	assert_eq(fallback.issued_calls[0]["units"], [member], "issued to the cluster's member")


func test_first_matching_rule_in_authored_order_wins() -> void:
	var first := SpyTacticRule.new()
	first.condition = StubCondition.new()
	(first.condition as StubCondition).result = true
	var second := SpyTacticRule.new()  # also unconditional — would match too, if reached
	var tactic := _tactic(GROUP, [first, second])
	_member()
	tactic._think()
	assert_eq(first.issued_calls.size(), 1, "earlier rule in the list takes priority")
	assert_eq(second.issued_calls.size(), 0, "later rule never even considered")


# --- Reissue gating --------------------------------------------------------------


func test_rule_change_redirects_every_current_member_even_a_busy_one() -> void:
	var defend := SpyTacticRule.new()
	var defend_condition := StubCondition.new()
	defend_condition.result = true
	defend.condition = defend_condition
	var attack := SpyTacticRule.new()
	var attack_condition := StubCondition.new()
	attack_condition.result = false
	attack.condition = attack_condition
	var tactic := _tactic(GROUP, [defend, attack])
	var a := _member()
	var b := _member()
	tactic._think()
	assert_eq(defend.issued_calls.size(), 1, "defend wins first, unconditionally issued")

	# Flip which rule is satisfied, and mark one member as actively busy — a rule CHANGE
	# must redirect the whole cluster regardless, unlike the same-rule/idle-only case below.
	defend_condition.result = false
	attack_condition.result = true
	var busy_command := MoveCommand.new(CommandMessage.new(null))
	a.update_commands(busy_command)
	assert_false(a.command_receiver.is_idle(), "test setup: a is busy")

	tactic._think()
	assert_eq(attack.issued_calls.size(), 1, "the new rule was issued")
	assert_eq(attack.issued_calls[0]["units"], [a, b], "to every member, busy or not")


func test_same_rule_only_reissues_to_members_that_went_idle() -> void:
	var fallback := SpyTacticRule.new()  # unconditional: stays the winning rule throughout
	var tactic := _tactic(GROUP, [fallback])
	var a := _member()
	var b := _member()

	tactic._think()
	assert_eq(fallback.issued_calls.size(), 1, "first tick: rule just became active, issues to all")
	assert_eq(fallback.issued_calls[0]["units"], [a, b])

	# Mark A busy (as if the earlier issue put it into a still-running Attack) and leave B
	# idle (as if its command finished with nothing queued behind it — the freeze bug).
	a.update_commands(MoveCommand.new(CommandMessage.new(null)))
	assert_false(a.command_receiver.is_idle())
	assert_true(b.command_receiver.is_idle())

	tactic._think()
	assert_eq(fallback.issued_calls.size(), 2, "same rule, but an idle member re-triggers it")
	assert_eq(fallback.issued_calls[1]["units"], [b], "only the idle member, A is left alone")


func test_same_rule_with_no_idle_members_does_not_reissue() -> void:
	var fallback := SpyTacticRule.new()
	var tactic := _tactic(GROUP, [fallback])
	var a := _member()
	tactic._think()
	assert_eq(fallback.issued_calls.size(), 1)

	a.update_commands(MoveCommand.new(CommandMessage.new(null)))
	tactic._think()
	assert_eq(fallback.issued_calls.size(), 1, "the only member is busy, nothing to re-task")


# --- Commander id plumbing --------------------------------------------------------


func test_commander_id_is_read_from_the_first_live_member() -> void:
	var fallback := SpyTacticRule.new()
	var tactic := _tactic(GROUP, [fallback])
	var a := _member()
	tactic._think()
	assert_eq(fallback.issued_calls[0]["commander_id"], a.commander_id)


# --- Cadence, claims and the scheduler ----------------------------------------------------


## A bot of `a_id` with a brain that has not built its managers: enough for claims and the
## combat period, without a map.
func _bot(a_id: int) -> Bot:
	var bot := Bot.new()
	bot.id = a_id
	add_child_autofree(bot)
	var brain := BotBrain.new()
	brain.name = "BotBrain"
	bot.add_child(brain)
	brain.set_physics_process(false)
	return bot


func _scenario_at(a_tick: int) -> Scenario:
	var scenario := Scenario.new()
	scenario.tick = a_tick
	_manager.scenario = scenario
	return scenario


func test_without_a_brain_it_decides_on_the_trigger_managers_cadence() -> void:
	var scenario: Scenario = _scenario_at(0)
	var fallback := SpyTacticRule.new()
	var tactic := _tactic(GROUP, [fallback])
	_member()
	tactic._physics_process(0.0)
	assert_eq(fallback.issued_calls.size(), 1, "decides at once")
	(_member() as Actor).add_to_group(GROUP)  # a newcomer, idle: due a re-issue
	tactic._physics_process(0.0)
	assert_eq(fallback.issued_calls.size(), 1, "but not again inside the period")
	scenario.tick = ScenarioTactic._fallback_period_ticks()
	tactic._physics_process(0.0)
	assert_eq(fallback.issued_calls.size(), 2, "and again once the period has passed")
	scenario.free()


func test_over_a_bot_it_is_a_scheduler_job_on_the_combat_period() -> void:
	var scenario: Scenario = _scenario_at(0)
	var bot: Bot = _bot(2)
	var fallback := SpyTacticRule.new()
	var tactic := _tactic(GROUP, [fallback])
	var unit: Actor = _member()
	unit.commander = bot
	tactic._physics_process(0.0)
	assert_eq(fallback.issued_calls.size(), 0, "the scheduler decides, not the frame")
	var scheduler: BotScheduler = tactic._scheduler
	assert_not_null(scheduler)
	var jobs: Array[BotJob] = scheduler.jobs_of(bot.brain())
	assert_eq(jobs.size(), 1)
	assert_eq(jobs[0].name, &"tactic")
	assert_eq(
		jobs[0].period_ticks(),
		roundi(bot.brain().config.combat_period_seconds * TimeUtils.ticks_per_second())
	)
	scheduler.step()
	assert_eq(fallback.issued_calls.size(), 1, "the job decides")
	tactic.free()
	assert_eq(scheduler.jobs_of(bot.brain()).size(), 0, "a freed tactic leaves no job behind")
	scheduler.free()
	scenario.free()


func test_a_switched_off_brain_falls_back_to_the_managers_cadence() -> void:
	var scenario: Scenario = _scenario_at(0)
	var bot: Bot = _bot(2)
	bot.brain().active = false
	var fallback := SpyTacticRule.new()
	var tactic := _tactic(GROUP, [fallback])
	_member().commander = bot
	tactic._physics_process(0.0)
	assert_eq(fallback.issued_calls.size(), 1, "the human's slot still runs its tactics")
	var scheduler: BotScheduler = tactic._scheduler
	tactic.free()
	if scheduler != null:
		scheduler.free()
	scenario.free()


func test_members_are_claimed_exclusively_and_released_with_the_tactic() -> void:
	var bot: Bot = _bot(2)
	var fallback := SpyTacticRule.new()
	var tactic := _tactic(GROUP, [fallback])
	var unit: Actor = _member()
	unit.commander = bot
	tactic._register_on(bot)
	tactic._think()
	var claims: BotClaims = bot.brain().claims
	assert_eq(claims.owner_of(unit), StringName("tactic:%s" % GROUP))
	assert_eq(claims.priority_of(unit), int(BotClaims.Priority.EXCLUSIVE))
	assert_false(
		claims.can_claim(unit, &"military", BotClaims.Priority.ERRAND), "no bot errand takes it"
	)
	var scheduler: BotScheduler = tactic._scheduler
	tactic.free()
	assert_false(claims.is_claimed(unit), "the claim goes with the tactic")
	if scheduler != null:
		scheduler.free()
