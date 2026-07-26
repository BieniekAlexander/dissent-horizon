@tool
class_name EventCommandPoint
extends EventCommand

## A follow-up command waypoint for a scenario event. Place these as children of
## an event (e.g. EventSpawnUnits); each one contributes one command to the chain
## issued to the spawned units, in scene-tree order. The command's destination is
## this node's global_position (snapped to the navmesh).
##
## The editor marker (a clickable Sprite3D, so it can be dragged in the viewport) comes
## from EditorMarkerSprite3D via EventCommand.

#region Properties
@export_enum("move", "attack_move", "defend") var command_type: String = "attack_move"
#endregion

#region Public API
func to_command(manager: ScenarioTriggerManager, post_offset: Vector3 = Vector3.ZERO) -> MoveCommand:
	var nav_map := manager.map.nav_region.get_navigation_map()
	var dest := NavigationServer3D.map_get_closest_point(nav_map, global_position + post_offset)
	var msg := CommandMessage.new(manager.map, null, null, dest)
	if command_type == "attack_move":
		return AttackMove.new(msg)
	if command_type == "defend":
		return Defend.new(msg)
	return MoveCommand.new(msg)
#endregion
