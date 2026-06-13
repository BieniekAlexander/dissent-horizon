class_name EventSpawnUnits
extends ScenarioEvent

@export var commander_id: int = 2
@export var scene: PackedScene
@export var count: int = 1
## Grid cell around which units appear. Actual placement is deconflicted via
## SpaceUtils so units never stack on spawn.
@export var spawn_grid_cell: Vector2i = Vector2i.ZERO
## If not (-1,-1), each spawned unit is issued this command immediately.
@export var move_to_grid_cell: Vector2i = Vector2i(-1, -1)
## Command to issue after spawn. "move" = basic move; "attack_move" = attack-move.
@export_enum("move", "attack_move") var move_command: String = "attack_move"

func execute(manager: ScenarioEventManager) -> void:
	if scene == null:
		return
	var commander := manager.get_commander(commander_id)
	if commander == null:
		return
	var map := manager.map
	if map == null:
		return

	var spawn_center := VU.inXZ(map.grid_to_world(spawn_grid_cell))

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

	if move_to_grid_cell == Vector2i(-1, -1):
		return

	# Snap the destination to the nearest navmesh point so the agents always have
	# a reachable target.
	var nav_map := map.nav_region.get_navigation_map()
	var dest := NavigationServer3D.map_get_closest_point(
		nav_map, map.grid_to_world(move_to_grid_cell)
	)

	for unit: Commandable in spawned:
		var msg := CommandMessage.new(map, null, null, dest)
		var cmd: Command = AttackMove.new(msg) if move_command == "attack_move" else Command.new(msg)
		unit.update_commands(cmd)
		# Prime the nav target immediately. CommandReceiver only calls
		# load_destination when the agent's target_position differs from the
		# command's — but a freshly spawned NavigationAgent3D defaults to (0,0,0).
		# When the destination is the map centre (also world origin), that guard
		# skips the load and the unit treats navigation as already finished,
		# dropping the command on its first tick. Setting the target explicitly
		# here kicks off path computation so the unit actually advances.
		unit.load_destination(cmd)
