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
## the cluster's lifetime, and synced each frame into the tactic's Squad.
##
## Children are TacticRule nodes, evaluated in authored order every physics frame. The first
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
## One policy per rule, built on arm, so the same rule is the same policy object.
var _policies: Dictionary = {}
var _registered_on: Commander = null


## Wire this tactic's rule conditions into the manager exactly as GlobalTrigger.arm() does:
## pull conditions register with the ConditionPoller, push conditions connect their bus, and
## a RegionAwareCondition gets its shape resolved (relative to the rule that owns it) so an
## authored region actually scopes the check instead of silently matching everywhere.
func arm(a_manager: ScenarioTriggerManager) -> void:
	_manager = a_manager
	_squad.name = unit_group
	_policies.clear()
	for rule: TacticRule in _rules():
		_policies[rule] = TacticRulePolicy.new(rule, a_manager)
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


func _physics_process(_a_delta: float) -> void:
	if _manager == null or unit_group.is_empty():
		return
	var members: Array[Actor] = _live_members()
	if members.is_empty():
		return
	_register_on(members[0].commander)
	_squad.set_members(members)
	var winner: TacticRule = _winning_rule()
	if winner == null:
		return
	_squad.policy = _policies[winner]
	_squad.tick()


func _register_on(a_commander: Commander) -> void:
	if a_commander == null or a_commander == _registered_on:
		return
	if _registered_on != null:
		_registered_on.squads.release(_squad)
	_registered_on = a_commander
	a_commander.squads.register(_squad)


func _exit_tree() -> void:
	if _registered_on != null:
		_registered_on.squads.release(_squad)
		_registered_on = null


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
