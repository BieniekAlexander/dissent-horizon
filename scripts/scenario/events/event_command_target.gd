@tool
class_name EventCommandTarget
extends EventCommand

## A follow-up command that dynamically selects a target cluster from the live game state.
## Clusters enemy commandables of the chosen Type using single-linkage agglomerative
## clustering (threshold 10.0 wu), selects one cluster by Priority, then issues a command at
## it: an AttackMove to the cluster's centroid for ARMY (units move, so a chase-the-area
## order fits), or an Attack locked onto one specific structure in the cluster for BASE
## (buildings don't move, and Attack — unlike AttackMove — never gets pulled onto a
## different target it passes near en route; see the comment in to_command()).
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

## Restricts candidates to entities whose Defense.frame_type matches this value, or -1 (the
## default) for no filter at all — e.g. Type.ARMY + BIO is "hunt down infantry
## specifically" rather than any enemy unit. A plain int rather than Defense.FrameType so
## "no filter" is expressible without colliding with FrameType's own values (BIO is 0).
@export var frame_filter: int = -1
#endregion

#region Public API
func to_command(a_manager: ScenarioTriggerManager, _a_post_offset: Vector3 = Vector3.ZERO) -> MoveCommand:
	var spawning_id: int = _spawning_commander_id()
	var candidates: Array = _enemy_candidates(a_manager, spawning_id)
	if candidates.is_empty():
		return null

	var clusters: Array = CU.get_nodes_clustered(candidates, _CLUSTER_DISTANCE_THRESHOLD)
	var selected: Array = _select_cluster(clusters, a_manager)
	if selected.is_empty():
		return null

	# Structures don't move and can't be stood inside, so a nav-snapped point near the
	# cluster's CENTROID (below, for ARMY) can land just outside a unit's short aggro/attack
	# range if the buildings' footprints push the snapped point away from any one of them —
	# the unit arrives, finds nothing in range under AttackMove's own logic, and idles. Locking
	# onto ONE specific structure with Attack sidesteps that: Attack.should_move() closes
	# distance until SU.is_in_attack_range() is actually true (the same check that already
	# works for a player's own structure-attack orders), and — unlike AttackMove — Attack never
	# picks up a different target it happens to pass near en route (Attack.get_updated_state()
	# only ever re-checks the SAME target; there is no aggro-reacquisition here at all), which
	# is what "beeline for structures, ignore units" actually needs.
	if type == Type.BASE:
		var target: Commandable = _closest_in(selected, global_position)
		var atk_msg := CommandMessage.new(a_manager.map, target, null, target.global_position)
		return Attack.new(atk_msg)

	var centroid: Vector3 = _centroid(selected)
	var nav_map: RID = a_manager.map.nav_region.get_navigation_map()
	var dest: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, centroid)
	var msg := CommandMessage.new(a_manager.map, null, null, dest)
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

func _enemy_candidates(a_manager: ScenarioTriggerManager, a_spawning_id: int) -> Array:
	var group: String = "structure" if type == Type.BASE else "unit"
	var result: Array = []
	for node in a_manager.get_tree().get_nodes_in_group(group):
		var c := node as Commandable
		if c == null:
			continue
		if c.commander_id == 0 or c.commander_id == a_spawning_id:
			continue
		if frame_filter >= 0 and (c.defense == null or c.defense.frame_type != frame_filter):
			continue
		result.append(c)
	return result

func _select_cluster(a_clusters: Array, _a_manager: ScenarioTriggerManager) -> Array:
	if a_clusters.is_empty():
		return []
	var ref_pos: Vector3 = global_position

	match priority:
		Priority.CLOSEST:
			return a_clusters.reduce(func(best: Array, c: Array) -> Array:
				return c if _centroid(c).distance_squared_to(ref_pos) < _centroid(best).distance_squared_to(ref_pos) else best
			)
		Priority.FARTHEST:
			return a_clusters.reduce(func(best: Array, c: Array) -> Array:
				return c if _centroid(c).distance_squared_to(ref_pos) > _centroid(best).distance_squared_to(ref_pos) else best
			)
		Priority.WEAKEST:
			return a_clusters.reduce(func(best: Array, c: Array) -> Array:
				return c if _total_hp(c) < _total_hp(best) else best
			)
		Priority.MOST_VALUABLE:
			return a_clusters.reduce(func(best: Array, c: Array) -> Array:
				return c if _total_hp_max(c) > _total_hp_max(best) else best
			)
	return a_clusters[0]

static func _centroid(cluster: Array) -> Vector3:
	var sum := Vector3.ZERO
	for node in cluster:
		sum += (node as Commandable).global_position
	return sum / float(cluster.size())

## The single member of `cluster` nearest to `ref_pos` — the specific entity an Attack (as
## opposed to an AttackMove toward the cluster's averaged centroid) locks onto.
static func _closest_in(cluster: Array, ref_pos: Vector3) -> Commandable:
	var best: Commandable = cluster[0]
	for node in cluster:
		var c := node as Commandable
		if c.global_position.distance_squared_to(ref_pos) < best.global_position.distance_squared_to(ref_pos):
			best = c
	return best

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
