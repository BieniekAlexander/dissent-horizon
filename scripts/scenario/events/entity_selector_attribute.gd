@tool
class_name EntitySelectorAttribute
extends EntitySelector

## Keeps entities according to whether they carry `attribute` in their attributes Set
## (Entity.Attribute — MECH / BIO / UNMANNED). With `require_present` true (default),
## keeps the entities that HAVE it; false keeps the entities that LACK it.

@export var attribute: Entity.Attribute = Entity.Attribute.MECH
@export var require_present: bool = true

func filter(entities: Array[Entity], _manager: ScenarioTriggerManager) -> Array[Entity]:
	var result: Array[Entity] = []
	result.assign(entities.filter(func(e: Entity) -> bool:
		var has: bool = e.attributes != null and e.attributes.contains(attribute)
		return has == require_present
	))
	return result
