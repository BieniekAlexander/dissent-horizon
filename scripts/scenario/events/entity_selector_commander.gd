@tool
class_name EntitySelectorCommander
extends EntitySelector

## Keeps only units owned by `commander_id`.

@export var commander_id: int = 0

func filter(units: Array[Commandable], _manager: ScenarioTriggerManager) -> Array[Commandable]:
	var result: Array[Commandable] = []
	result.assign(units.filter(func(u: Commandable) -> bool: return u.commander_id == commander_id))
	return result
