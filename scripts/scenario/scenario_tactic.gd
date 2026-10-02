@tool
class_name ScenarioTactic
extends Node

## Ongoing, hand-authored behaviour for one cluster of scenario-spawned units — the gap
## between the Bot (governs a whole skirmish commander, untouched by this) and
## EventIssueCommand (issues one command chain, once, with nothing watching afterward). See
## gdd/tasks.md, "Command Assignment extensions".
##
## A cluster is identified by node-group membership (`unit_group`), stamped onto units the
## same way EventSpawnEntities.spawn_groups labels a wave for ConditionGroupCount — fixed for
## the cluster's lifetime; merging or splitting clusters is explicitly out of scope here.
##
## Children are TacticRule nodes, evaluated in authored order every physics frame. The first
## whose condition holds (or which has none at all — an unconditional fallback) is the
## cluster's CURRENT rule. Re-issuing is split two ways, deliberately not "reissue whenever
## the current rule is still true":
##  - the rule CHANGING redirects every current member — a real change of posture.
##  - the rule staying the same but a member going IDLE (its command queue ran dry — an
##    Attack whose target died, an AttackMove that arrived and found nothing) re-runs that
##    SAME rule for that member ALONE, so a dynamically-targeted command like
##    EventCommandTarget's "attack the nearest cluster" gets a fresh target instead of the
##    unit freezing forever — the bug that motivated this. Members still actively executing
##    their order are left alone; only the idle ones are touched.
##
## Add as a sibling of GlobalTrigger under a ScenarioTriggerManager.

@export var unit_group: StringName = &""

var _manager: ScenarioTriggerManager
var _active_rule: TacticRule = null


## Wire this tactic's rule conditions into the manager exactly as GlobalTrigger.arm() does:
## pull conditions register with the ConditionPoller, push conditions connect their bus, and
## a RegionAwareCondition gets its shape resolved (relative to the rule that owns it) so an
## authored region actually scopes the check instead of silently matching everywhere.
func arm(a_manager: ScenarioTriggerManager) -> void:
	_manager = a_manager
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
	_active_rule = null
	for rule: TacticRule in _rules():
		if rule.condition != null:
			rule.condition.reset()


func _physics_process(_a_delta: float) -> void:
	if _manager == null or unit_group.is_empty():
		return
	var members: Array[Commandable] = _live_members()
	if members.is_empty():
		return
	var winner: TacticRule = _winning_rule()
	if winner == null:
		return
	var commander_id: int = members[0].commander_id
	if winner != _active_rule:
		_active_rule = winner
		winner.issue_commands_to(members, _manager, commander_id)
		return
	var idle_members: Array[Commandable] = members.filter(
		func(m: Commandable) -> bool: return m.command_receiver.is_idle()
	)
	if not idle_members.is_empty():
		winner.issue_commands_to(idle_members, _manager, commander_id)


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
func _live_members() -> Array[Commandable]:
	var result: Array[Commandable] = []
	for node: Node in get_tree().get_nodes_in_group(unit_group):
		if node.is_queued_for_deletion():
			continue
		var c := node as Commandable
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
