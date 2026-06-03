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
## (e.g. units). Garrisoned units are placed in a ring around the owner,
## spaced just outside its Layer.BODY collision radius, then issued a movement
## command to that same spawn position so the command clears immediately.
func _evacuate_from_unit(owner_cmd: Commandable, a_map: Map) -> void:
	var count := _garrisoned.size()
	for i in range(count):
		var unit: Commandable = _garrisoned[i]
		var spawn_pos := SU.ring_spawn_position(owner_cmd, unit, i, count, a_map)

		unit.commander.add_child(unit)
		unit.global_position = spawn_pos

		if a_map != null:
			unit.update_commands(Command.new(CommandMessage.new(a_map, null, null, spawn_pos)))
