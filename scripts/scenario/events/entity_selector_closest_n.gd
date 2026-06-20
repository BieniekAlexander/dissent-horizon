@tool
class_name EntitySelectorClosestN
extends EntitySelector

## Keeps at most `count` units closest to `origin` (or this node's own position if null).

@export var count: int = 1
@export var origin: Node3D

func filter(units: Array[Commandable], _manager: ScenarioTriggerManager) -> Array[Commandable]:
	if units.is_empty() or count <= 0:
		return []
	var ref_pos: Vector3 = origin.global_position if origin != null else global_position
	var sorted: Array = AU.sort_on_key(
		func(u: Commandable) -> float: return u.global_position.distance_squared_to(ref_pos),
		units
	)
	var result: Array[Commandable] = []
	result.assign(sorted.slice(0, count))
	return result
