@tool
class_name EntitySelectorAttribute
extends EntitySelector

## Keeps units according to whether they carry `attribute` in their attributes Set
## (Entity.Attribute — MECH / BIO / UNMANNED). With `require_present` true (default),
## keeps the units that HAVE it; false keeps the units that LACK it.

@export var attribute: Entity.Attribute = Entity.Attribute.MECH
@export var require_present: bool = true

func filter(units: Array[Commandable], _manager: ScenarioTriggerManager) -> Array[Commandable]:
	var result: Array[Commandable] = []
	result.assign(units.filter(func(u: Commandable) -> bool:
		var has: bool = u.attributes != null and u.attributes.contains(attribute)
		return has == require_present
	))
	return result
