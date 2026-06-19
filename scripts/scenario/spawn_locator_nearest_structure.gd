@tool
class_name SpawnLocatorNearestStructure
extends SpawnLocator

## Anchors the event at the nearest structure to the source entity — e.g. "on death,
## spawn reinforcements at our closest building." Restrict to a commander with
## commander_id (>= 0); -1 considers any structure. Falls back to the source's own
## position when no matching structure exists.

@export var commander_id: int = -1

func resolve(source: Entity, manager: ScenarioTriggerManager) -> Vector3:
	if source == null:
		return Vector3.ZERO
	var origin: Vector3 = source.global_position
	var best: Vector3 = origin
	var best_distance: float = INF
	for node in manager.get_tree().get_nodes_in_group("structure"):
		var structure := node as Commandable
		if structure == null:
			continue
		if commander_id >= 0 and structure.commander_id != commander_id:
			continue
		var d: float = origin.distance_squared_to(structure.global_position)
		if d < best_distance:
			best_distance = d
			best = structure.global_position
	return best
