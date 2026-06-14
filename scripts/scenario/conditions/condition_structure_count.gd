class_name ConditionStructureCount
extends Condition

#region Properties
enum Comparison { AT_LEAST, AT_MOST, EXACTLY }

@export var commander_id: int = 1
## UNDEFINED matches structures of any type.
@export var structure_type: Entity.Type = Entity.Type.UNDEFINED
@export var comparison: Comparison = Comparison.AT_LEAST
@export var count: int = 1
#endregion

#region Public API
func evaluate(manager: ScenarioEventManager) -> bool:
	var commander: Commander = manager.get_commander(commander_id)
	if commander == null:
		return false
	var n := 0
	if structure_type == Entity.Type.UNDEFINED:
		for t: int in Entity.Type.values():
			if t < 0:
				continue  # skip UNDEFINED
			n += commander.structure_type_map[t].size()
	else:
		n = commander.structure_type_map[structure_type].size()
	match comparison:
		Comparison.AT_LEAST: return n >= count
		Comparison.AT_MOST:  return n <= count
		Comparison.EXACTLY:  return n == count
	return false
#endregion
