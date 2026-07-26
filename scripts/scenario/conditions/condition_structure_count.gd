class_name ConditionStructureCount
extends Condition

#region Properties
enum Comparison { AT_LEAST, AT_MOST, EXACTLY }

@export var commander_id: int = 1
## UNDEFINED matches structures of any type.
@export var structure_type: StringName = &""
@export var comparison: Comparison = Comparison.AT_LEAST
@export var count: int = 1
#endregion

#region Public API
func evaluate(manager: ScenarioTriggerManager) -> bool:
	var commander: Commander = manager.get_commander(commander_id)
	if commander == null:
		return false
	# NOTE: counts ALL structures including those under construction. This is
	# intentional for AT_MOST victory checks (a half-built enemy structure still
	# exists and should prevent victory), but may be surprising for AT_LEAST
	# economic triggers where only built structures provide income. Gate on
	# Commandable.is_built inside the loop if a specific condition needs it.
	var n := 0
	if structure_type == &"":
		for t: StringName in commander.structure_type_map:
			n += commander.structure_type_map[t].size()
	else:
		var s: Variant = commander.structure_type_map.get(structure_type)
		n = s.size() if s != null else 0
	match comparison:
		Comparison.AT_LEAST: return n >= count
		Comparison.AT_MOST:  return n <= count
		Comparison.EXACTLY:  return n == count
	return false
#endregion
