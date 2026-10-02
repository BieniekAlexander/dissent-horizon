@tool
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
func evaluate(a_manager: ScenarioTriggerManager) -> bool:
	var commander: Commander = a_manager.get_commander(commander_id)
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
			n += (
				commander
				. structure_type_map[t]
				. filter(func(c: Commandable): return c.is_built)
				. size()
			)
	else:
		var s: Variant = commander.structure_type_map.get(structure_type)
		n = s.filter(func(c: Commandable): return c.is_built).size() if s != null else 0
	match comparison:
		Comparison.AT_LEAST:
			return n >= count
		Comparison.AT_MOST:
			return n <= count
		Comparison.EXACTLY:
			return n == count
	return false


#endregion


#region Player-facing description (highlights)
## Same rule as ConditionUnitCount: AT_MOST means "remove these", so the standing
## structures are the task and get marked. AT_LEAST / EXACTLY are waiting on a building
## that doesn't exist yet, and there is nothing to point at.
func highlight_entities(a_manager: ScenarioTriggerManager) -> Array[Entity]:
	var result: Array[Entity] = []
	if comparison != Comparison.AT_MOST:
		return result
	var commander: Commander = a_manager.get_commander(commander_id)
	if commander == null:
		return result
	for id: StringName in commander.structure_type_map:
		if structure_type != &"" and id != structure_type:
			continue
		for structure: Variant in commander.structure_type_map[id].get_values():
			var entity := structure as Entity
			if entity != null and is_instance_valid(entity) and entity.is_inside_tree():
				result.append(entity)
	return result
#endregion
