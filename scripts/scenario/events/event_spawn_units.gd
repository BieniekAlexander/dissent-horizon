@tool
class_name EventSpawnUnits
extends ScenarioEvent

## Spawns `count` instances of `scene` for `commander_id` at this node's
## global_position. Each EventCommandPoint child (in scene-tree order) adds one
## command to the chain issued to every spawned unit.

#region Constants
const _SPAWN_RING_RADIUS := 1.0
#endregion

#region Properties
@export var commander_id: int = 2
@export var scene: PackedScene
@export var count: int = 1
#endregion

#region Public API
func execute(manager: ScenarioEventManager) -> void:
	if scene == null:
		return
	var commander := manager.get_commander(commander_id)
	if commander == null:
		return
	var map := manager.map
	if map == null:
		return

	var spawn_center := VU.inXZ(global_position)

	var spawned: Array[Commandable] = []
	for _i in range(count):
		var entity := scene.instantiate()
		if entity is Commandable:
			spawned.append(entity)
		else:
			entity.queue_free()
	if spawned.is_empty():
		return

	map.add_entities(spawned, spawn_center, commander)

	# Follow-up command chain: one command per EventCommand child, in
	# scene-tree order. No commands → units just spawn and idle.
	var event_commands: Array[EventCommand] = _event_commands()
	if event_commands.is_empty():
		return

	for unit: Commandable in spawned:
		var chain: Array[Command] = []
		for ec: EventCommand in event_commands:
			var cmd: Command = ec.to_command(manager)
			if cmd != null:
				chain.append(cmd)
		if chain.is_empty():
			continue
		unit.update_commands(chain)
		# Prime the nav target immediately. CommandReceiver only calls
		# load_destination when the agent's target_position differs from the
		# command's — but a freshly spawned NavigationAgent3D defaults to (0,0,0).
		# When the destination is the map centre (also world origin), that guard
		# skips the load and the unit treats navigation as already finished,
		# dropping the command on its first tick. Setting the target explicitly
		# here kicks off path computation so the unit actually advances.
		unit.load_destination(chain[0])
#endregion

#region Private helpers
## Direct EventCommand children, in scene-tree order.
func _event_commands() -> Array[EventCommand]:
	var result: Array[EventCommand] = []
	for child in get_children():
		if child is EventCommand:
			result.append(child)
	return result
#endregion

#region Editor gizmo
func _draw_editor_gizmo(verts: PackedVector3Array) -> void:
	_gizmo_ring(verts, Vector3.ZERO, _SPAWN_RING_RADIUS)
	# Polyline from the spawn point through each EventCommandPoint child (local space).
	# EventCommandTarget nodes don't have a fixed position, so only waypoints are drawn.
	var path: Array[Vector3] = [Vector3.ZERO]
	for child in get_children():
		if child is EventCommandPoint:
			path.append((child as EventCommandPoint).position)
	_gizmo_polyline(verts, path)
#endregion
