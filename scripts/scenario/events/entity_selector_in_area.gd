@tool
class_name EntitySelectorInArea
extends EntitySelector

## Keeps only units whose CharacterBody3D is overlapping `area`.
## The Area3D must have an appropriate collision_mask to detect units.

@export var area: Area3D

func filter(units: Array[Commandable], _manager: ScenarioTriggerManager) -> Array[Commandable]:
	if area == null:
		return units
	var bodies: Array[Node3D] = area.get_overlapping_bodies()
	var in_area: Dictionary = {}
	for b: Node3D in bodies:
		in_area[b] = true
	var result: Array[Commandable] = []
	result.assign(units.filter(func(u: Commandable) -> bool: return in_area.has(u)))
	return result
