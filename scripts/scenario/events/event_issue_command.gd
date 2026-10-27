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

## Each unit's post is WHERE IT STANDS when the order is given, not a formation fanned around
## the last command point: "the Recruits placed at the outpost defend where they were placed",
## so an author's exact placement survives the order. Added for prologue mission 1 (Alex,
## 2026-10-21), whose start-time pieces are placed in the scene rather than spawned.
@export var should_post_in_place: bool = false

## EventCommandPoint kinds that act where the unit already is, so they name no post.
const PLACELESS: Array[String] = ["land", "evacuate", "leave_map"]

var _commander_id_context: int = -1


func execute(a_manager: ScenarioTriggerManager) -> void:
	if get_parent() is EventSpawnEntities:
		return
	var entities: Array[Entity] = _all_scene_entities(a_manager)
	for sel: EntitySelector in _selectors():
		entities = sel.filter(entities, a_manager)
	# The selector pipeline is Entity-typed, but commands only apply to Commandables —
	# narrow to them here (the Actor predicate at the command-issuing boundary).
	var units: Array[Actor] = []
	for entity: Entity in entities:
		if entity is Actor:
			units.append(entity)
	issue_commands_to(units, a_manager)


## Issues the EventCommand chain (built from EventCommand child nodes) to `units`.
## `p_commander_id_context` is the owning commander's id — available to EventCommandTarget
## via active_commander_id() while the call is in progress.
func issue_commands_to(
	a_units: Array[Actor], a_manager: ScenarioTriggerManager, a_p_commander_id_context: int = -1
) -> void:
	_commander_id_context = a_p_commander_id_context
	var event_commands: Array[EventCommand] = _event_commands()
	var aggro_override: CollisionShape3D = _aggro_shape_override()
	# One planar offset per unit so the group fans into a formation around the command
	# point(s) instead of every unit converging on the identical post (which, with the
	# nav-based arrival check, would leave them swirling and never settling).
	var offsets: Array[Vector3] = _formation_offsets(a_units, a_manager, event_commands)
	if not event_commands.is_empty():
		for i: int in a_units.size():
			var unit: Actor = a_units[i]
			var offset: Vector3 = offsets[i]
			var chain: Array[MoveCommand] = []
			for ec: EventCommand in event_commands:
				var cmd: MoveCommand = ec.to_command(a_manager, offset)
				if cmd != null:
					if aggro_override != null and cmd is Defend:
						cmd.message.aggro_shape = aggro_override
					chain.append(cmd)
			if chain.is_empty():
				continue
			# Through the mission's actuator, the one audited surface a computer commander
			# orders by, which also primes the nav target.
			a_manager.mission_actuator().issue_chain(unit, chain)
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


func _all_scene_entities(a_manager: ScenarioTriggerManager) -> Array[Entity]:
	var result: Array[Entity] = []
	for node: Node in a_manager.get_tree().get_nodes_in_group("unit"):
		var e: Entity = node as Entity
		if e != null:
			result.append(e)
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


## A per-unit planar offset (index-aligned with `units`) that spreads the group into a
## non-overlapping formation around the final command point, so each unit ends at its own
## post rather than every unit converging on one shared point. Returns all-zero offsets for
## a single unit or when the chain has no positional post to anchor on.
func _formation_offsets(
	a_units: Array[Actor], a_manager: ScenarioTriggerManager, a_event_commands: Array[EventCommand]
) -> Array[Vector3]:
	var offsets: Array[Vector3] = []
	# The last point that is a POST: a Land or an Evacuate has none of its own (it acts where the
	# chain has brought the unit), a LeaveMap's is off the board, and a point aimed at a
	# commander's unit is where that unit stands.
	var anchor: EventCommandPoint = null
	for ec: EventCommand in a_event_commands:
		if ec is EventCommandPoint and not (ec as EventCommandPoint).command_type in PLACELESS:
			anchor = ec as EventCommandPoint
	if should_post_in_place and anchor != null:
		var at: Vector3 = anchor.destination(a_manager)
		for unit: Actor in a_units:
			offsets.append(VU.on_xz(unit.global_position - at))
		return offsets
	if a_units.size() <= 1 or anchor == null or a_manager.map == null:
		for _u: Actor in a_units:
			offsets.append(Vector3.ZERO)
		return offsets
	var map: Map = a_manager.map
	var radius: float = a_units[0].bounding_radius(CollisionLayers.Mask.MOVEMENT_OBSTRUCTION)
	var region_radius: float = maxf(5.0, radius * 2.5 * float(a_units.size()))
	var anchor_xz: Vector2 = VU.in_xz(anchor.destination(a_manager))
	var points: Array[Vector2] = SU.get_nonoverlapping_points(
		map,
		anchor_xz,
		radius,
		map.get_world_3d(),
		CollisionLayers.Mask.MOVEMENT_OBSTRUCTION,
		region_radius,
		a_units.size()
	)
	for i: int in a_units.size():
		if i < points.size():
			var d: Vector2 = points[i] - anchor_xz
			offsets.append(Vector3(d.x, 0.0, d.y))
		else:
			offsets.append(Vector3.ZERO)
	return offsets
