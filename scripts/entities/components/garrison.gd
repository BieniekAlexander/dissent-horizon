class_name Garrison
extends Node

## Garrison component — allows a Commandable to hold units inside it.
##
## Garrisoned units are removed from the active scene tree (so they don't
## participate in physics, rendering, AI, or fog-of-war) but kept alive via
## the _garrisoned array reference.  On evacuation they are re-inserted under
## their original Commander node and dispersed to nearby open cells.

#region Properties
## Maximum number of units that may garrison simultaneously.
@export var capacity: int = 4
## When true, garrisoned units can fire their weapons from inside this garrison.
## The garrison owner's position and AggroRange are used; garrisoned units supply
## the weapons. Set false for purely protective garrisons that offer no fire support.
@export var bunker: bool = true

## Units currently garrisoned.  Held as orphaned nodes — removed from the
## scene tree but not freed.
var _garrisoned: Array[Commandable] = []

## When a commanderless (neutral) garrison is garrisoned, it temporarily adopts
## the garrisoning units' commander. `_adopted_commander` records that this
## happened so we can revert on full evacuation; `_restore_commander` holds the
## original (neutral) commander to revert to. A garrison that already had a real
## commander never adopts, so it is left untouched on evacuation.
var _adopted_commander: bool = false
var _restore_commander: Commander = null
#endregion

#region Public API
## True when at least one more unit can be accepted.
func can_garrison() -> bool:
	return _garrisoned.size() < capacity

func garrisoned_count() -> int:
	return _garrisoned.size()

## True when at least one garrisoned unit carries a weapon that can target `target`.
func any_garrison_can_target(target: Entity) -> bool:
	if not bunker:
		return false
	for unit: Commandable in _garrisoned:
		if unit.weapon_inventory != null and unit.weapon_inventory.weapon_for_target(target) != null:
			return true
	return false

## Fire eligible garrisoned units at `target` from `owner`'s world position.
## Call once per physics tick while an Attack command is active. Manages each
## unit's attack_timer independently since orphaned units don't tick themselves.
func tick_bunker_fire(owner: Commandable, target: Entity) -> void:
	if not bunker:
		return
	for unit: Commandable in _garrisoned:
		if unit.weapon_inventory == null:
			continue
		var weapon := unit.weapon_inventory.weapon_for_target(target)
		if weapon == null:
			continue
		if not SU.is_weapon_in_range_at(weapon, owner.global_transform, owner.get_world_3d(), target, owner):
			continue
		unit.attack_timer = weapon.attack_duration
		unit._attack_duration = weapon.attack_duration
		weapon.fire(owner, target)


## Remove `unit` from the active scene tree and store it here.
func garrison(unit: Commandable) -> void:
	_adopt_commander_if_neutral(unit)
	unit.get_parent().remove_child(unit)
	_garrisoned.append(unit)


## When this garrison has no commander (neutral, id 0), adopt the garrisoning
## unit's commander so the structure reads as that team's while occupied. The
## original (neutral) commander is remembered so evacuation can revert it. Only
## the first garrisoning unit triggers the adoption; subsequent units share the
## same commander (enforced by the Occupy precondition), so this is a no-op
## for them. A garrison that already had a real commander is never touched.
func _adopt_commander_if_neutral(unit: Commandable) -> void:
	if _adopted_commander:
		return
	var owner_cmd := get_parent() as Commandable
	if owner_cmd == null or owner_cmd.commander_id != 0:
		return
	if unit.commander == null:
		return
	_restore_commander = owner_cmd.commander
	_adopted_commander = true
	owner_cmd.commander = unit.commander


## Restore all garrisoned units to the scene tree.
## Routes to the appropriate placement strategy depending on whether the
## garrison owner occupies the terrain grid (has an Obstruction component) or
## is itself a non-grid entity such as a unit.
func evacuate(a_map: Map) -> void:
	var owner_cmd := get_parent() as Commandable

	if owner_cmd != null and owner_cmd.has_node("Obstruction"):
		_evacuate_from_structure(owner_cmd, a_map)
	else:
		_evacuate_from_unit(owner_cmd, a_map)

	_garrisoned.clear()
	_revert_adopted_commander(owner_cmd)


## Revert a commander adopted from garrisoning units once everyone has left, so
## the garrison returns to neutral. No-op when the garrison had its own commander
## to begin with (it was never adopted), so a preexisting commander is preserved.
func _revert_adopted_commander(owner_cmd: Commandable) -> void:
	if not _adopted_commander:
		return
	if owner_cmd != null:
		owner_cmd.commander = _restore_commander
	_adopted_commander = false
	_restore_commander = null
#endregion

#region Private helpers
## Evacuation path for garrison owners that occupy the terrain grid (structures).
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


## Evacuation path for garrison owners that do NOT occupy the terrain grid
## (e.g. units). Garrisoned units are spread around the owner via
## SpaceUtils.get_nonoverlapping_points — each gets a distinct point clear of
## existing bodies and on valid navmesh — then issued a movement command to
## that spawn position so the command clears immediately.
func _evacuate_from_unit(owner_cmd: Commandable, a_map: Map) -> void:
	var count := _garrisoned.size()
	var center := VU.inXZ(owner_cmd.global_position)
	var radius: float = owner_cmd.bounding_radius(CollisionLayers.Mask.MOVEMENT_OBSTRUCTION)

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
			CollisionLayers.Mask.MOVEMENT_OBSTRUCTION,
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
#endregion
