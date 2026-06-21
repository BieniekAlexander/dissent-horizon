@tool
class_name EntitySelectorCommander
extends EntitySelector

## Keeps only entities owned by `commander_id`.

@export var commander_id: int = 0

func filter(entities: Array[Entity], _manager: ScenarioTriggerManager) -> Array[Entity]:
	var result: Array[Entity] = []
	result.assign(entities.filter(func(e: Entity) -> bool: return e.commander_id == commander_id))
	return result
