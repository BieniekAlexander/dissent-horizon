@tool
class_name SpawnLocatorNearestStructure
extends SpawnLocator

## Anchors the event at the nearest structure to the source entity — e.g. "on death,
## spawn reinforcements at our closest building." Restrict to a commander with
## commander_id (>= 0); -1 considers any structure. Falls back to the source's own
## position when no matching structure exists.

@export var commander_id: int = -1


func resolve(a_source: Entity, a_manager: ScenarioTriggerManager) -> Vector3:
	if a_source == null:
		return Vector3.ZERO
	var origin: Vector3 = a_source.global_position
	var best: Vector3 = origin
	var best_distance: float = INF
	for node in a_manager.get_tree().get_nodes_in_group("fixture"):
		# ENTITY, not Actor. A structure need not be a Actor — an ExtractionSite, a
		# A Shelter is a plain Entity carrying a Structure component — and `as Actor` on
		# one yields null SILENTLY, so narrowing here quietly excluded every feature from "the
		# nearest structure" while the docstring above promised `commander_id = -1` would
		# consider any of them. structure_is_active() is the fixture test.
		var structure := node as Entity
		if structure == null or not structure.structure_is_active():
			continue
		if commander_id >= 0 and structure.commander_id != commander_id:
			continue
		var d: float = origin.distance_squared_to(structure.global_position)
		if d < best_distance:
			best_distance = d
			best = structure.global_position
	return best
