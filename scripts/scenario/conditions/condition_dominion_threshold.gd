@tool
class_name ConditionDominionThreshold
extends Condition

#region Properties
enum Comparison { AT_LEAST, AT_MOST }

@export var commander_id: int = 1
@export var comparison: Comparison = Comparison.AT_LEAST
@export var amount: int = 1000
#endregion

#region Public API
func evaluate(a_manager: ScenarioTriggerManager) -> bool:
	var commander: Commander = a_manager.get_commander(commander_id)
	if commander == null:
		return false
	match comparison:
		Comparison.AT_LEAST: return commander.dominion >= amount
		Comparison.AT_MOST:  return commander.dominion <= amount
	return false
#endregion
