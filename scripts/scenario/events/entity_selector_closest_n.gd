@tool
class_name EntitySelectorClosestN
extends EntitySelector

## Keeps at most `count` entities closest to `origin` (or this node's own position if null).

@export var count: int = 1
@export var origin: Node3D

func filter(entities: Array[Entity], _manager: ScenarioTriggerManager) -> Array[Entity]:
	if entities.is_empty() or count <= 0:
		return []
	var ref_pos: Vector3 = origin.global_position if origin != null else global_position
	var sorted: Array = AU.sort_on_key(
		func(e: Entity) -> float: return e.global_position.distance_squared_to(ref_pos),
		entities
	)
	var result: Array[Entity] = []
	result.assign(sorted.slice(0, count))
	return result
