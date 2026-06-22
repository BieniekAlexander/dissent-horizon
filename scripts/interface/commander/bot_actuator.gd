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


## Order each unit to attack a specific enemy entity directly. persist=false makes
## it a leashed engagement (drop the target if it flees / leaves range), so the unit
## returns to idle — and gets re-tasked — instead of chasing forever.
func attack(units: Array, target: Entity, persist: bool = true) -> void:
	if _map == null or target == null:
		return
	for u: Commandable in units:
		var msg := CommandMessage.new(_map, target)
		msg.persist = persist
		var cmd := Attack.new(msg)
		u.update_commands(cmd)
		u.load_destination(cmd)


## Order a builder to place a structure of `type` at a world position. For a Mine
## (overlay), world_pos must sit on the target Deposit's cell. Tech/resource/
## placement validity are enforced downstream by Build.meets_precondition, so an
## invalid request is a safe no-op (the builder just won't complete it).
func build(builder: Commandable, type: Entity.Type, world_pos: Vector3) -> bool:
	var tool := Tool.for_type(type)
	if tool == null:
		return false
	var cmd := Build.new(CommandMessage.new(_map, null, tool, world_pos))
	builder.update_commands(cmd)
	builder.load_destination(cmd)
	return true


## Queue one unit of `type` at a production structure. Returns false only when no
## tool produces `type`; affordability + cost deduction are enforced downstream by
## Commandable._process_commands (which routes Train into the Production queue and
## calls commander.use_resources_for), so a too-expensive request is a safe no-op.
func train(structure: Commandable, type: Entity.Type) -> bool:
	var tool := Tool.for_type(type)
	if tool == null:
		return false
	structure.update_commands(Train.new(CommandMessage.new(_map, null, tool)))
	return true
