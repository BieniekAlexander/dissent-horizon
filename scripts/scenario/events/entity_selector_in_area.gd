@tool
class_name EntitySelectorInArea
extends EntitySelector

## Keeps only entities whose CharacterBody3D is overlapping `area`.
## The Area3D must have an appropriate collision_mask to detect them.

@export var area: Area3D

func filter(entities: Array[Entity], _manager: ScenarioTriggerManager) -> Array[Entity]:
	if area == null:
		return entities
	var bodies: Array[Node3D] = area.get_overlapping_bodies()
	var in_area: Dictionary = {}
	for b: Node3D in bodies:
		in_area[b] = true
	var result: Array[Entity] = []
	result.assign(entities.filter(func(e: Entity) -> bool: return in_area.has(e)))
	return result
