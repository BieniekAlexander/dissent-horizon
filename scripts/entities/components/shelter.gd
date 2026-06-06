class_name Shelter
extends Node

## Garrison component — allows a Commandable to hold units inside it.
##
## Garrisoned units are removed from the active scene tree (so they don't
## participate in physics, rendering, AI, or fog-of-war) but kept alive via
## the _garrisoned array reference.  On evacuation they are re-inserted under
## their original Commander node and dispersed to nearby open cells.

## Maximum number of units that may garrison simultaneously.
@export var capacity: int = 4

## Units currently garrisoned.  Held as orphaned nodes — removed from the
## scene tree but not freed.
var _garrisoned: Array[Commandable] = []


## True when at least one more unit can be accepted.
func can_garrison() -> bool:
	return _garrisoned.size() < capacity

func garrisoned_count() -> int:
	return _garrisoned.size()


## Remove `unit` from the active scene tree and store it here.
func garrison(unit: Commandable) -> void:
	unit.get_parent().remove_child(unit)
	_garrisoned.append(unit)


## Restore all garrisoned units to the scene tree.
## Routes to the appropriate placement strategy depending on whether the
## shelter owner occupies the terrain grid (has an Obstruction component) or
## is itself a non-grid entity such as a unit.
func evacuate(a_map: Map) -> void:
	var owner_cmd := get_parent() as Commandable

	if owner_cmd != null and owner_cmd.has_node("Obstruction"):
		_evacuate_from_structure(owner_cmd, a_map)
	else:
		_evacuate_from_unit(owner_cmd, a_map)

	_garrisoned.clear()


## Evacuation path for shelter owners that occupy the terrain grid (structures).
## Each unit is placed at the footprint-boundary cell closest to its randomly
## assigned destination so it appears to exit from the correct side.
func _evacuate_from_structure(owner_cmd: Commandable, a_map: Map) -> void:
	# Build the candidate list once; pop_front() gives each unit a unique cell.
	var open_cells := SU.passable_cells_adjacent_to(owner_cmd, a_map)

	for unit: Commandable in _garrisoned:
		# Pick a destination — each unit gets its own cell where possible.
		var dest: Vector3
		if open_cells.is_empty():
			# Fallback: converge on the structure's world position; the physics
			# collision system will push them apart from there.
			dest = owner_cmd.global_position
		else:
			dest = a_map.grid_to_world(open_cells.pop_front())

		# Spawn at the boundary cell closest to the destination so the unit
		# exits from the correct side of the building.
		var spawn_cell := SU.nearest_footprint_adjacent_cell(dest, owner_cmd, a_map)

		unit.commander.add_child(unit)

		if spawn_cell != Vector2i(-1, -1):
			var spawn_xz := a_map.grid_to_world(spawn_cell)
			var height_offset := unit.movement.height_offset() if unit.movement != null else 0.0
			unit.global_position = Vector3(
				spawn_xz.x,
				a_map.terrain_height_at(VU.inXZ(spawn_xz)) + height_offset,
				spawn_xz.z
			)

		unit.update_commands(Command.new(CommandMessage.new(a_map, null, null, dest)))


## Evacuation path for shelter owners that do NOT occupy the terrain grid
## (e.g. units). Garrisoned units are spread around the owner via
## SpaceUtils.get_nonoverlapping_points — each gets a distinct point clear of
## existing bodies and on valid navmesh — then issued a movement command to
## that spawn position so the command clears immediately.
func _evacuate_from_unit(owner_cmd: Commandable, a_map: Map) -> void:
	var count := _garrisoned.size()
	var center := VU.inXZ(owner_cmd.global_position)
	var radius: float = owner_cmd.bounding_radius(CollisionLayers.Layer.MOVEMENT_OBSTRUCTION)

	# Generate one spawn point per garrisoned unit around the owner. Size the
	# search region off the owner's radius and the count so a large garrison
	# still finds room.
	var points: Array[Vector2] = []
	if a_map != null:
		var region_radius: float = 30. # maxf(5.0, radius * 2.5 * float(maxi(count, 1)))
		points = SU.get_nonoverlapping_points(
			a_map,
			center,
			radius,
			a_map.get_world_3d(),
			CollisionLayers.Layer.MOVEMENT_OBSTRUCTION,
			region_radius,
			count
		)

	# get_nonoverlapping_points may return fewer points than requested when the
	# area is crowded (and we have no points at all without a map). Every unit
	# still needs its OWN evacuation point, so fan the leftovers out on a ring
	# of distinct angles around the owner; physics resolves any residual overlap.
	while points.size() < count:
		var leftover_index := points.size()
		var angle: float = 2.0 * PI * float(leftover_index) / float(maxi(count, 1))
		var ring_radius: float = 2.0 * radius * (1.0 + float(leftover_index) / float(maxi(count, 1)))
		points.append(center + Vector2(cos(angle), sin(angle)) * ring_radius)

	for i in range(count):
		var unit: Commandable = _garrisoned[i]
		var spawn_xz: Vector2 = points[i]
		var height_offset: float = unit.movement.height_offset() if unit.movement != null else 0.0
		var y: float = a_map.terrain_height_at(spawn_xz) + height_offset \
			if a_map != null else owner_cmd.global_position.y
		var spawn_pos := Vector3(spawn_xz.x, y, spawn_xz.y)

		unit.commander.add_child(unit)
		unit.global_position = spawn_pos

		if a_map != null:
			unit.update_commands(Command.new(CommandMessage.new(a_map, null, null, spawn_pos)))
