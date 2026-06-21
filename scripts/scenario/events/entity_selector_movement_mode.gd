@tool
class_name EntitySelectorMovementMode
extends EntitySelector

## Keeps only entities whose Movement.mode matches `mode` (those without a Movement
## component are dropped).

@export var mode: Movement.Mode = Movement.Mode.GROUNDED_DIRECT

func filter(entities: Array[Entity], _manager: ScenarioTriggerManager) -> Array[Entity]:
	var result: Array[Entity] = []
	result.assign(entities.filter(func(e: Entity) -> bool:
		return e.movement != null and e.movement.mode == mode
	))
	return result
