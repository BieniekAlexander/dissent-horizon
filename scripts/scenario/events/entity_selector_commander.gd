@tool
class_name EntitySelectorCommander
extends EntitySelector

## Keeps only entities owned by `commander_id`.

@export var commander_id: int = 0


func filter(a_entities: Array[Entity], _a_manager: ScenarioTriggerManager) -> Array[Entity]:
	var result: Array[Entity] = []
	result.assign(a_entities.filter(func(e: Entity) -> bool: return e.commander_id == commander_id))
	return result
