@tool
class_name EventCommandPoint
extends EventCommand

## A follow-up command waypoint for a scenario event. Place these as children of
## an event (e.g. EventSpawnUnits); each one contributes one command to the chain
## issued to the spawned units, in scene-tree order. The command's destination is
## this node's global_position (snapped to the navmesh).
##
## `land` sets an aircraft down where the chain has brought it (Land): placed after a move, it
## makes "fly in and land there" (Alex, 2026-10-18). Its own position is not used.
##
## `near_commander_id` aims the point at a commander's pieces instead of at itself: at the
## position of that commander's unit NEAREST this node when the order is given — "land near the
## player", wherever the player's army stands by then. This node's position is then only where
## the search starts, and the fallback when that commander has no unit.
##
## `evacuate` turns the host's garrison out where the chain has brought it (Evacuate), setting a
## hovering transport down first: placed after a move, it makes "fly in and drop the squad
## there". Its own position is not used either.
##
## `leave_map` flies the unit to THIS node's position, unsnapped, and removes it once it is off
## the map (LeaveMap): place the node beyond the map edge, for a transport that goes home.
##
## The editor marker (a clickable Sprite3D, so it can be dragged in the viewport) comes
## from EditorMarkerSprite3D via EventCommand.

#region Properties
@export_enum("move", "attack_move", "defend", "land", "evacuate", "leave_map")
var command_type: String = "attack_move"
## A commander whose nearest unit the point moves to when the order is given; -1 for none.
@export var near_commander_id: int = -1
## With `near_commander_id`: how far short of that unit the point stops, back toward this node —
## "beside the player", not on top of them.
@export var near_standoff: float = 0.0
#endregion


#region Public API
func to_command(
	a_manager: ScenarioTriggerManager, a_post_offset: Vector3 = Vector3.ZERO
) -> MoveCommand:
	if command_type == "land":
		return Land.new(CommandMessage.new(a_manager.map, null, null, global_position))
	if command_type == "evacuate":
		return Evacuate.new(CommandMessage.new(a_manager.map, null, null, global_position))
	if command_type == "leave_map":
		return LeaveMap.new(CommandMessage.new(a_manager.map, null, null, global_position))
	var nav_map := a_manager.map.nav_region.get_navigation_map()
	var dest := NavigationServer3D.map_get_closest_point(
		nav_map, destination(a_manager) + a_post_offset
	)
	var msg := CommandMessage.new(a_manager.map, null, null, dest)
	if command_type == "attack_move":
		return AttackMove.new(msg)
	if command_type == "defend":
		return Defend.new(msg)
	return MoveCommand.new(msg)


## Where the command goes: this node's position, or, with `near_commander_id`, the position of
## that commander's unit nearest it. Units are taken in tree order, so ties resolve the same on
## every machine.
func destination(a_manager: ScenarioTriggerManager) -> Vector3:
	var commander: Commander = (
		a_manager.get_commander(near_commander_id) if near_commander_id >= 0 else null
	)
	if commander == null:
		return global_position
	var here: Vector2 = VU.in_xz(global_position)
	var best: Variant = null
	var best_distance: float = INF
	for node: Node in a_manager.get_tree().get_nodes_in_group("unit"):
		var unit := node as Actor
		if unit == null or not unit.is_inside_tree() or unit.commander != commander:
			continue
		var distance: float = here.distance_squared_to(VU.in_xz(unit.global_position))
		if distance < best_distance:
			best_distance = distance
			best = unit.global_position
	if best == null:
		return global_position
	var back: Vector2 = here - VU.in_xz(best)
	if near_standoff <= 0.0 or back.length() <= near_standoff:
		return best
	return best + VU.from_xz(back.normalized() * near_standoff)
#endregion
