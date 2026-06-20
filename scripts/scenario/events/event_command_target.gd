@tool
class_name EventCommandTarget
extends EventCommand

## A follow-up command that dynamically selects a target cluster from the live
## game state. Clusters enemy commandables of the chosen Type using single-linkage
## agglomerative clustering (threshold 10.0 wu), then issues an AttackMove to the
## centroid of the cluster selected by Priority.
##
## Attach as a child of EventSpawnUnits (alongside or instead of EventCommandPoints).

#region Constants
const _CLUSTER_DISTANCE_THRESHOLD := 10.0
#endregion

#region Enums
## Which enemy entity group to cluster.
enum Type {
	BASE,  ## Structures (is_in_group("structure"))
	ARMY   ## Units (is_in_group("unit"))
}

## How to rank the resulting clusters when selecting one.
enum Priority {
	CLOSEST,       ## Cluster whose centroid is nearest to the spawn point
	FARTHEST,      ## Cluster whose centroid is farthest from the spawn point
	WEAKEST,       ## Cluster with the lowest total current HP
	MOST_VALUABLE  ## Cluster with the highest total max HP
}
#endregion

#region Properties
@export var type: Type = Type.BASE
@export var priority: Priority = Priority.CLOSEST
#endregion

#region Public API
func to_command(manager: ScenarioTriggerManager) -> Command:
	var spawning_id: int = _spawning_commander_id()
	var candidates: Array = _enemy_candidates(manager, spawning_id)
	if candidates.is_empty():
		return null

	var clusters: Array = CU.get_nodes_clustered(candidates, _CLUSTER_DISTANCE_THRESHOLD)
	var selected: Array = _select_cluster(clusters, manager)
	if selected.is_empty():
		return null

	var centroid: Vector3 = _centroid(selected)
	var nav_map: RID = manager.map.nav_region.get_navigation_map()
	var dest: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, centroid)
	var msg := CommandMessage.new(manager.map, null, null, dest)
	return AttackMove.new(msg)
#endregion

#region Private helpers
func _spawning_commander_id() -> int:
	var p: Node = get_parent()
	if p is EventIssueCommand:
		return (p as EventIssueCommand).active_commander_id()
	if p is EventSpawnEntities:
		return (p as EventSpawnEntities).commander_id
	return 0

func _enemy_candidates(manager: ScenarioTriggerManager, spawning_id: int) -> Array:
	var group: String = "structure" if type == Type.BASE else "unit"
	var result: Array = []
	for node in manager.get_tree().get_nodes_in_group(group):
		var c := node as Commandable
		if c == null:
			continue
		if c.commander_id == 0 or c.commander_id == spawning_id:
			continue
		result.append(c)
	return result

func _select_cluster(clusters: Array, manager: ScenarioTriggerManager) -> Array:
	if clusters.is_empty():
		return []
	var ref_pos: Vector3 = global_position

	match priority:
		Priority.CLOSEST:
			return clusters.reduce(func(best: Array, c: Array) -> Array:
				return c if _centroid(c).distance_squared_to(ref_pos) < _centroid(best).distance_squared_to(ref_pos) else best
			)
		Priority.FARTHEST:
			return clusters.reduce(func(best: Array, c: Array) -> Array:
				return c if _centroid(c).distance_squared_to(ref_pos) > _centroid(best).distance_squared_to(ref_pos) else best
			)
		Priority.WEAKEST:
			return clusters.reduce(func(best: Array, c: Array) -> Array:
				return c if _total_hp(c) < _total_hp(best) else best
			)
		Priority.MOST_VALUABLE:
			return clusters.reduce(func(best: Array, c: Array) -> Array:
				return c if _total_hp_max(c) > _total_hp_max(best) else best
			)
	return clusters[0]

static func _centroid(cluster: Array) -> Vector3:
	var sum := Vector3.ZERO
	for node in cluster:
		sum += (node as Commandable).global_position
	return sum / float(cluster.size())

static func _total_hp(cluster: Array) -> float:
	var total: float = 0.0
	for node in cluster:
		var c := node as Commandable
		if c.defense != null:
			total += c.defense.hp
	return total

static func _total_hp_max(cluster: Array) -> float:
	var total: float = 0.0
	for node in cluster:
		var c := node as Commandable
		if c.defense != null:
			total += c.defense.hp_max
	return total
#endregion
