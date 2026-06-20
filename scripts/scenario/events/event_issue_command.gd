@tool
class_name EventIssueCommand
extends AbstractEvent

## Issues a command chain to a selected set of units.
##
## Standalone use (fired by a Trigger): EntitySelector child nodes are applied as a
## pipeline — each narrows the previous output — to pick which units receive commands.
## The seed is all units currently in the scene.
##
## Nested under EventSpawnEntities: execute() is skipped entirely. The parent calls
## issue_commands_to() directly with the freshly-spawned units, bypassing the selector
## pipeline (the recipient list is already known).

var _commander_id_context: int = -1


func execute(manager: ScenarioTriggerManager) -> void:
	if get_parent() is EventSpawnEntities:
		return
	var units: Array[Commandable] = _all_scene_units(manager)
	for sel: EntitySelector in _selectors():
		units = sel.filter(units, manager)
	issue_commands_to(units, manager)


## Issues the EventCommand chain (built from EventCommand child nodes) to `units`.
## `p_commander_id_context` is the owning commander's id — available to EventCommandTarget
## via active_commander_id() while the call is in progress.
func issue_commands_to(units: Array[Commandable], manager: ScenarioTriggerManager, p_commander_id_context: int = -1) -> void:
	_commander_id_context = p_commander_id_context
	var event_commands: Array[EventCommand] = _event_commands()
	var aggro_override: CollisionShape3D = _aggro_shape_override()
	if not event_commands.is_empty():
		for unit: Commandable in units:
			var chain: Array[Command] = []
			for ec: EventCommand in event_commands:
				var cmd: Command = ec.to_command(manager)
				if cmd != null:
					if aggro_override != null and cmd is Defend:
						cmd.message.aggro_shape = aggro_override
					chain.append(cmd)
			if chain.is_empty():
				continue
			unit.update_commands(chain)
			# Prime the nav target immediately so a destination at the map centre (world
			# origin) isn't silently dropped: NavigationAgent3D defaults target_position
			# to (0,0,0), matching the centre, so the guard in CommandReceiver skips
			# load_destination and the unit treats navigation as already finished.
			unit.load_destination(chain[0])
	_commander_id_context = -1


## Returns the commander id in effect during the current issue_commands_to() call, or
## the id from the first EntitySelectorCommander child when called outside one.
## Used by EventCommandTarget to identify the right enemies to target.
func active_commander_id() -> int:
	if _commander_id_context >= 0:
		return _commander_id_context
	for child: Node in get_children():
		if child is EntitySelectorCommander:
			return (child as EntitySelectorCommander).commander_id
	return 0


func _all_scene_units(manager: ScenarioTriggerManager) -> Array[Commandable]:
	var result: Array[Commandable] = []
	for node: Node in manager.get_tree().get_nodes_in_group("unit"):
		var c: Commandable = node as Commandable
		if c != null:
			result.append(c)
	return result


func _selectors() -> Array[EntitySelector]:
	var result: Array[EntitySelector] = []
	for child: Node in get_children():
		if child is EntitySelector:
			result.append(child as EntitySelector)
	return result


func _event_commands() -> Array[EventCommand]:
	var result: Array[EventCommand] = []
	for child: Node in get_children():
		if child is EventCommand:
			result.append(child as EventCommand)
	return result


func _aggro_shape_override() -> CollisionShape3D:
	for child: Node in get_children():
		if child is CollisionShape3D:
			return child as CollisionShape3D
	return null
