@tool
class_name EntitySelectorMovementMode
extends EntitySelector

## Keeps only units whose Movement.mode matches `mode`.

@export var mode: Movement.Mode = Movement.Mode.GROUNDED_DIRECT

func filter(units: Array[Commandable], _manager: ScenarioTriggerManager) -> Array[Commandable]:
	var result: Array[Commandable] = []
	result.assign(units.filter(func(u: Commandable) -> bool:
		return u.movement != null and u.movement.mode == mode
	))
	return result
