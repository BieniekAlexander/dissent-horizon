@tool
class_name EventSpawnUnits
extends ScenarioEvent

## Spawns `count` instances of `scene` for `commander_id` at this node's
## global_position. Each EventCommandPoint child (in scene-tree order) adds one
## command to the chain issued to every spawned unit.

@export var commander_id: int = 2
@export var scene: PackedScene
@export var count: int = 1

const _SPAWN_RING_RADIUS := 1.0


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

	# Instantiate first so we can read the unit's collision radius for spacing.
	var spawned: Array[Commandable] = []
	for _i in range(count):
		var entity := scene.instantiate()
		if entity is Commandable:
			spawned.append(entity)
		else:
			entity.queue_free()
	if spawned.is_empty():
		return

	# Pre-compute mutually non-overlapping spawn points. map.add_entity runs its
	# own overlap check per unit, but that check can't see siblings spawned in the
	# SAME physics frame (they aren't registered with the physics server until the
	# next step), so a naive loop stacks them. SpaceUtils.get_nonoverlapping_points
	# generates points spaced apart by construction (and clear of existing bodies),
	# so the whole batch lands without overlap.
	var radius: float = spawned[0].bounding_radius(CollisionLayers.Mask.MOVEMENT_OBSTRUCTION)
	var region_radius: float = maxf(5.0, radius * 2.5 * float(maxi(count, 1)))
	var points: Array[Vector2] = SU.get_nonoverlapping_points(
		map,
		spawn_center,
		radius,
		map.get_world_3d(),
		CollisionLayers.Mask.MOVEMENT_OBSTRUCTION,
		region_radius,
		spawned.size()
	)

	for i in spawned.size():
		var place_xz: Vector2 = points[i] if i < points.size() else spawn_center
		map.add_entity(spawned[i], place_xz, commander)

	# Follow-up command chain: one command per EventCommandPoint child, in
	# scene-tree order. No points → units just spawn and idle.
	var command_points: Array[EventCommandPoint] = _command_points()
	if command_points.is_empty():
		return

	for unit: Commandable in spawned:
		var chain: Array[Command] = []
		for point: EventCommandPoint in command_points:
			chain.append(point.to_command(map))
		unit.update_commands(chain)
		# Prime the nav target immediately. CommandReceiver only calls
		# load_destination when the agent's target_position differs from the
		# command's — but a freshly spawned NavigationAgent3D defaults to (0,0,0).
		# When the destination is the map centre (also world origin), that guard
		# skips the load and the unit treats navigation as already finished,
		# dropping the command on its first tick. Setting the target explicitly
		# here kicks off path computation so the unit actually advances.
		unit.load_destination(chain[0])


## Direct EventCommandPoint children, in scene-tree order.
func _command_points() -> Array[EventCommandPoint]:
	var result: Array[EventCommandPoint] = []
	for child in get_children():
		if child is EventCommandPoint:
			result.append(child)
	return result


func _draw_editor_gizmo(verts: PackedVector3Array) -> void:
	_gizmo_ring(verts, Vector3.ZERO, _SPAWN_RING_RADIUS)
	# Polyline from the spawn point through each command point (local space).
	var path: Array[Vector3] = [Vector3.ZERO]
	for point: EventCommandPoint in _command_points():
		path.append(point.position)
	_gizmo_polyline(verts, path)
