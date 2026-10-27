@tool
class_name EntitySelectorGroup
extends EntitySelector

## Keeps only entities in the scene-tree group `group` — the label a spawner stamps
## (EventSpawnEntities.spawn_groups) or an author puts on a scene-placed piece. Lets one
## EventIssueCommand order exactly the pieces a mission placed for a beat, the way
## ConditionGroupCount counts them.

@export var group: StringName = &""


func filter(a_entities: Array[Entity], _a_manager: ScenarioTriggerManager) -> Array[Entity]:
	var result: Array[Entity] = []
	if group.is_empty():
		return result
	result.assign(a_entities.filter(func(e: Entity) -> bool: return e.is_in_group(group)))
	return result
