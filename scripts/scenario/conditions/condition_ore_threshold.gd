class_name ConditionOreThreshold
extends Condition

#region Properties
enum Comparison { AT_LEAST, AT_MOST }

@export var commander_id: int = 1
@export var comparison: Comparison = Comparison.AT_LEAST
@export var amount: int = 500
#endregion

#region Public API
func evaluate(manager: ScenarioTriggerManager) -> bool:
	var commander: Commander = manager.get_commander(commander_id)
	if commander == null:
		return false
	match comparison:
		Comparison.AT_LEAST: return commander.ore >= amount
		Comparison.AT_MOST:  return commander.ore <= amount
	return false
#endregion
