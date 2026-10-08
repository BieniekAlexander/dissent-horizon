class_name TacticRulePolicy
extends SquadPolicy

## A mission's authored rule as a squad policy: issuing it runs the rule's command chain
## for the members handed over (`TacticRule.issue_commands_to`), exactly as ScenarioTactic
## did before squads existed. Two policies are the same order iff they wrap the same rule,
## which is the "rule changing redirects every member; the same rule re-runs for the idle"
## split ScenarioTactic documents — the split is now Squad.tick's.

var rule: TacticRule
var _manager: ScenarioTriggerManager


func _init(a_rule: TacticRule, a_manager: ScenarioTriggerManager) -> void:
	rule = a_rule
	_manager = a_manager


func issue(a_members: Array) -> void:
	var typed: Array[Commandable] = []
	typed.assign(a_members)
	rule.issue_commands_to(typed, _manager, typed[0].commander_id)


func same_as(a_other: SquadPolicy) -> bool:
	return a_other is TacticRulePolicy and (a_other as TacticRulePolicy).rule == rule


func kind() -> StringName:
	return &"tactic"
