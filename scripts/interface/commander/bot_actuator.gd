class_name BotActuator
extends RefCounted

## BotActuator — the ONLY place the bot mutates game state.
##
## The strategy managers (military / production / economy) decide WHAT to do by
## reading the Bot's perception; they call into this thin layer to actually issue
## commands. Keeping all command construction here means the decision code stays
## pure and testable, and there's a single audited surface for "the bot did a
## thing". Mirrors the proven programmatic command paths (EventCommandPoint /
## EventIssueCommand): build a CommandMessage, wrap it in a Command, then
## update_commands + load_destination so the nav target is primed.

var _map: Map


func _init(a_map: Map) -> void:
	_map = a_map


## Order each unit to attack-move toward a world position. The destination is
## snapped to the navmesh first (a raw point off the mesh would be dropped).
## Attack-move makes units engage enemies encountered en route.
func attack_move(units: Array, world_pos: Vector3) -> void:
	if _map == null:
		return
	var dest: Vector3 = _map.nearest_navmesh_point(world_pos)
	for u: Commandable in units:
		var cmd := AttackMove.new(CommandMessage.new(_map, null, null, dest))
		u.update_commands(cmd)
		# Prime the nav target: a fresh agent defaults target_position to (0,0,0),
		# so without this a destination at the map centre is silently dropped.
		u.load_destination(cmd)


## Order each unit to attack a specific enemy entity directly.
func attack(units: Array, target: Entity) -> void:
	if _map == null or target == null:
		return
	for u: Commandable in units:
		var cmd := Attack.new(CommandMessage.new(_map, target))
		u.update_commands(cmd)
		u.load_destination(cmd)


## Queue one unit of `type` at a production structure. Returns false only when no
## tool produces `type`; affordability + cost deduction are enforced downstream by
## Commandable._process_commands (which routes Train into the Production queue and
## calls commander.use_resources_for), so a too-expensive request is a safe no-op.
func train(structure: Commandable, type: Entity.Type) -> bool:
	var tool := _tool_for_type(type)
	if tool == null:
		return false
	structure.update_commands(Train.new(CommandMessage.new(_map, null, tool)))
	return true


## Find the Tool whose produced type matches, so Train carries the right scene.
func _tool_for_type(type: Variant) -> Tool:
	for tool: Tool in Tool.command_tool_map.values():
		if tool != null and tool.type == type and tool.packed_scene != null:
			return tool
	return null
