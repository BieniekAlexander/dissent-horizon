@tool
class_name ScenarioTactic
extends Node

## Ongoing, hand-authored behaviour for one cluster of scenario-spawned units — the gap
## between the Bot (governs a whole skirmish commander, untouched by this) and
## EventIssueCommand (issues one command chain, once, with nothing watching afterward). See
## gdd/systems/scenario-scripting/tactics.md.
##
## A cluster is identified by node-group membership (`unit_group`), stamped onto units the
## same way EventSpawnEntities.spawn_groups labels a wave for ConditionGroupCount — fixed for
## the cluster's lifetime, and synced into the tactic's Squad each time it decides. Its
## members are claimed EXCLUSIVELY in their bot's BotClaims, so a slot can run the Bot's own
## military beside a scripted squad without the army's sweep re-tasking it.
##
## It decides on its commander's combat period, as a BotScheduler job, so a scripted squad
## reacts at the slot's difficulty; a commander with no running brain has the trigger manager's
## own cadence instead (see _physics_process).
##
## Children are TacticRule nodes, evaluated in authored order each time it decides. The first
## whose condition holds (or which has none at all — an unconditional fallback) is the
## cluster's CURRENT rule, and becomes the squad's policy (TacticRulePolicy). The dispatch
## is Squad.tick's, shared with the Bot's military — the rule CHANGING redirects every
## member (a real change of posture); the same rule re-runs only for a member that went
## IDLE (an Attack whose target died, an AttackMove that arrived and found nothing), so a
## dynamically-targeted command like EventCommandTarget's "attack the nearest cluster" gets
## a fresh target instead of the unit freezing forever — the bug that motivated this. Which
## rule wins is the decision side and stays authored here:
## gdd/systems/ai/squads-and-relations.md §The boundary.
##
## Add as a sibling of GlobalTrigger under a ScenarioTriggerManager.

@export var unit_group: StringName = &""

var _manager: ScenarioTriggerManager
## The cluster as a squad. Registered on its members' commander once the first live member
## is seen, so the commander's registry lists it beside the Bot's own.
var _squad: Squad = Squad.new()
## One policy per rule, built the first time the rule wins on the current commander (a policy
## that steers through the bot's senses needs that commander's Bot), so the same rule is the
## same policy object until the cluster changes hands. A rule whose policy cannot be built
## maps to null.
var _policies: Dictionary = {}
var _registered_on: Commander = null
## The scheduler job that paces this tactic while its commander's brain runs; null otherwise.
var _job: BotJob = null
## The scheduler `_job` is registered with. Held rather than looked up by group, since a
## scheduler made this frame joins the tree deferred.
var _scheduler: BotScheduler = null
## The scenario tick the trigger manager's cadence next runs `_think` at, when not scheduled.
var _next_tick: int = 0


## Wire this tactic's rule conditions into the manager exactly as GlobalTrigger.arm() does:
## pull conditions register with the ConditionPoller, push conditions connect their bus, and
## a RegionAwareCondition gets its shape resolved (relative to the rule that owns it) so an
## authored region actually scopes the check instead of silently matching everywhere.
func arm(a_manager: ScenarioTriggerManager) -> void:
	_manager = a_manager
	_squad.name = unit_group
	_policies.clear()
	for rule: TacticRule in _rules():
		var condition: Condition = rule.condition
		if condition == null:
			continue
		if condition is RegionAwareCondition:
			var region_aware := condition as RegionAwareCondition
			region_aware.bind_region(
				rule.get_node_or_null(region_aware.region_shape_path) as CollisionShape3D
			)
			region_aware.warn_about_missing_region(String(rule.name))
		condition.arm(a_manager)


## Drop every rule condition's runtime state, so this tactic starts with nothing carried
## over from a previous session. The tactic counterpart of GlobalTrigger.reset_conditions();
## see ScenarioTriggerManager._reset_session_conditions() for why it is needed at all.
func reset_conditions() -> void:
	_squad.policy = null
	_squad.redirect()
	for rule: TacticRule in _rules():
		if rule.condition != null:
			rule.condition.reset()


## Pace the tactic. Over a bot whose brain runs, the session's BotScheduler runs `_think` on
## that bot's combat period, so a scripted squad reacts at the slot's difficulty like the bot's
## own; otherwise (the human's slot, neutral, a brain switched off) it runs here on the trigger
## manager's own cadence, ScenarioTriggerManager.TACTIC_PERIOD_SECONDS.
func _physics_process(_a_delta: float) -> void:
	if _manager == null or unit_group.is_empty():
		return
	var members: Array[Actor] = _live_members()
	if members.is_empty():
		return
	_register_on(members[0].commander)
	if _is_scheduled():
		return
	var now: int = _manager.scenario.tick if _manager.scenario != null else 0
	if now < _next_tick:
		return
	_next_tick = now + _fallback_period_ticks()
	_think()


## One decision: sync the cluster into the squad, keep it claimed, and keep it to the winning
## rule. Returns the work units spent, for the scheduler.
func _think() -> int:
	var members: Array[Actor] = _live_members()
	if members.is_empty():
		return BotBrain.IDLE_JOB_WORK_UNITS
	_squad.set_members(members)
	_claim(members)
	var winner: TacticRule = _winning_rule()
	var policy: SquadPolicy = _policy_for(winner) if winner != null else null
	if policy != null:
		_squad.policy = policy
		_squad.reason = String(winner.name)
		_squad.tick()
	return members.size() * BotMilitary.UNIT_WORK_UNITS


## The trigger manager's cadence in ticks, converted here at the boundary.
static func _fallback_period_ticks() -> int:
	return maxi(
		1, roundi(ScenarioTriggerManager.TACTIC_PERIOD_SECONDS * TimeUtils.ticks_per_second())
	)


## Whether the scheduler is pacing this tactic right now: registered on a bot whose brain runs.
func _is_scheduled() -> bool:
	return _job != null and is_instance_valid(_job.brain) and _job.brain.active


## Hold every member EXCLUSIVELY in its bot's claims, so no bot manager — the military's idle
## sweep, targeting, an errand — orders a unit the mission is steering. A commander with no
## brain has no claims to keep.
func _claim(a_members: Array[Actor]) -> void:
	var brain: BotBrain = _brain_of(_registered_on)
	if brain == null:
		return
	for member: Actor in a_members:
		brain.claims.claim(member, _claim_owner(), BotClaims.Priority.EXCLUSIVE)


func _claim_owner() -> StringName:
	return StringName("tactic:%s" % unit_group)


static func _brain_of(commander: Commander) -> BotBrain:
	var bot := commander as Bot
	return bot.brain() if bot != null else null


func _register_on(a_commander: Commander) -> void:
	if a_commander == null or a_commander == _registered_on:
		return
	_unregister()
	_policies.clear()
	_registered_on = a_commander
	a_commander.squads.register(_squad)
	var brain: BotBrain = _brain_of(a_commander)
	if brain == null:
		return
	_job = BotJob.new(
		&"tactic",
		brain,
		func() -> float: return brain.config.combat_period_seconds,
		BotBrain.JOB_PRIORITY_MILITARY,
		func(_a_allowance: int) -> int: return _think()
	)
	_scheduler = BotScheduler.find_or_create(self, _manager)
	_scheduler.register(_job)


## Give back the squad, the claims and the scheduled job, so nothing calls into this tactic
## after it has gone or moved to another commander.
func _unregister() -> void:
	if _registered_on == null:
		return
	_registered_on.squads.release(_squad)
	var brain: BotBrain = _brain_of(_registered_on)
	if brain != null:
		for member: Variant in _squad.members():
			brain.claims.release(member, _claim_owner())
	if _job != null and is_instance_valid(_scheduler):
		_scheduler.unregister(_job)
	_job = null
	_scheduler = null
	_registered_on = null


func _exit_tree() -> void:
	_unregister()


## The cluster as a squad: what an ESCORT rule on another tactic carries.
func squad() -> Squad:
	return _squad


func _policy_for(a_rule: TacticRule) -> SquadPolicy:
	if not _policies.has(a_rule):
		_policies[a_rule] = _build_policy(a_rule)
	return _policies[a_rule]


## `a_rule`'s action as the shared policy, or null (with a warning) when the rule lacks what it
## needs — a point, the squad it escorts — or the commander is not a Bot whose senses the policy
## steers by. An authored point is fixed, so a post compares exactly (epsilon 0).
func _build_policy(a_rule: TacticRule) -> SquadPolicy:
	var act: BotActuator = _manager.mission_actuator()
	var bot := _registered_on as Bot
	var at: Variant = a_rule.point()
	var problem: String = ""
	var policy: SquadPolicy = null
	match a_rule.action:
		TacticRule.Action.COMMANDS:
			policy = TacticRulePolicy.new(a_rule, _manager)
		TacticRule.Action.HOLD, TacticRule.Action.STAGE, TacticRule.Action.ASSAULT:
			if at == null:
				problem = "names no point"
			elif a_rule.action == TacticRule.Action.HOLD:
				policy = HoldPolicy.new(act, at, 0.0)
			elif a_rule.action == TacticRule.Action.STAGE:
				policy = StagePolicy.new(act, at, 0.0)
			else:
				policy = AssaultPolicy.new(bot, act, at, null, 0, 0.0)
		TacticRule.Action.ESCORT:
			var served := a_rule.get_node_or_null(a_rule.escort_of) as ScenarioTactic
			if served == null:
				problem = "names no tactic to escort"
			elif bot == null:
				problem = "belongs to a commander that is not a Bot"
			else:
				policy = EscortPolicy.new(bot, act, Relation.transport(), served.squad())
		TacticRule.Action.RETREAT:
			if bot == null:
				problem = "belongs to a commander that is not a Bot"
			else:
				policy = RetreatPolicy.new(bot, act, at)
		TacticRule.Action.BUILD:
			if at == null or a_rule.structure_type.is_empty():
				problem = "names no point or no structure type"
			else:
				policy = BuildPolicy.new(act, a_rule.structure_type, at)
	if policy == null:
		push_warning(
			(
				"ScenarioTactic %s: rule %s (%s) %s, so it does nothing."
				% [name, a_rule.name, TacticRule.Action.find_key(a_rule.action), problem]
			)
		)
	return policy


func _rules() -> Array[TacticRule]:
	var result: Array[TacticRule] = []
	for child: Node in get_children():
		if child is TacticRule:
			result.append(child as TacticRule)
	return result


## The cluster's current members: live Commandables still in `unit_group`. Casualties drop
## out on their own — a dead unit leaves every group along with the rest of the scene tree —
## so no explicit pruning is needed, the same reasoning ConditionGroupCount relies on for a
## group count.
func _live_members() -> Array[Actor]:
	var result: Array[Actor] = []
	for node: Node in get_tree().get_nodes_in_group(unit_group):
		if node.is_queued_for_deletion():
			continue
		var c := node as Actor
		if c != null:
			result.append(c)
	return result


## First rule, in authored order, whose condition currently holds. A rule with no condition
## always matches — place one last for a cluster's default it can never fall through past.
## Conditions are queried live via evaluate() (documented idempotent, safe to call every
## frame) rather than the poller's cached is_met(), so a rule's truth is never a frame stale
## relative to the reissue decision made from it this same tick.
func _winning_rule() -> TacticRule:
	for rule: TacticRule in _rules():
		if rule.condition == null or rule.condition.evaluate(_manager):
			return rule
	return null
