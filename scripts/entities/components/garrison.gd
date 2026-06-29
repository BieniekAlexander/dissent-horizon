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
## When true, garrisoned units are evacuated (returned to the scene) when the host
## dies. When false they die with the host. Defaults to true so garrisons are a
## safe haven rather than a death trap.
@export var preserve_occupants: bool = true

## Units currently garrisoned.  Held as orphaned nodes — removed from the
## scene tree but not freed.
var _garrisoned: Array[Commandable] = []

## Saved radius of the host's AggroRange shape before any unit garrisoned.
## -1.0 means "nothing has garrisoned yet / already restored".
var _original_aggro_radius: float = -1.0

## Units that have registered intent to garrison this shelter while it lands.
## Each entry auto-removes itself via tree_exiting when the unit dies.
var _pending_garrison_units: Array[Commandable] = []

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

## Register `unit` as intending to garrison once this shelter touches down.
## Idempotent — a second call for the same unit is silently ignored.
## Connects to tree_exiting so a unit that dies auto-removes itself.
func register_garrison_intent(unit: Commandable) -> void:
	if unit in _pending_garrison_units:
		return
	_pending_garrison_units.append(unit)
	unit.tree_exiting.connect(unregister_garrison_intent.bind(unit))

## Remove `unit` from the pending list and drop the tree_exiting connection.
## When the list becomes empty and the host is already grounded, lifts off so
## the host resumes normal HOVERING without needing an explicit player command.
func unregister_garrison_intent(unit: Commandable) -> void:
	_pending_garrison_units.erase(unit)
	if unit.tree_exiting.is_connected(unregister_garrison_intent.bind(unit)):
		unit.tree_exiting.disconnect(unregister_garrison_intent.bind(unit))
	if _pending_garrison_units.is_empty():
		var owner_cmd := get_parent() as Commandable
		if owner_cmd != null and owner_cmd.movement != null:
			owner_cmd.movement.take_off()

## Tell all pending units to drop their garrison command, then clear the list.
## Called when the shelter receives a new command while units are waiting.
func cancel_pending_garrison() -> void:
	var pending: Array[Commandable] = _pending_garrison_units.duplicate()
	for unit: Commandable in pending:
		unregister_garrison_intent(unit)
		if is_instance_valid(unit):
			unit.update_commands(null)

func garrisoned_count() -> int:
	return _garrisoned.size()

## Free all garrisoned units without returning them to the scene.
## Used when preserve_occupants is false and the host is destroyed.
func kill_occupants() -> void:
	for unit: Commandable in _garrisoned:
		if is_instance_valid(unit):
			unit.queue_free()
	_garrisoned.clear()

## True when at least one garrisoned unit carries a weapon that can target `target`.
func any_garrison_can_target(target: Entity) -> bool:
	if not bunker:
		return false
	for unit: Commandable in _garrisoned:
		if unit.weapon_inventory != null and unit.weapon_inventory.weapon_for_target(target) != null:
			return true
	return false

## Fire every garrisoned unit's first target-capable weapon at `target` from
## `owner`'s world position, for those weapons that are loaded and in range.
## Each weapon advances its own reload timer in Weapon._physics_process because
## its Loadout was reparented onto `owner` at garrison time (see garrison()), so
## firing simply respects Weapon.is_ready() rather than tracking timers here.
func tick_bunker_fire(owner: Commandable, target: Entity) -> void:
	if not bunker:
		return
	for unit: Commandable in _garrisoned:
		var weapon := _firing_weapon(unit, owner, target)
		if weapon != null:
			weapon.fire(owner, target)


## True when at least one garrisoned unit carries a weapon that can target, is
## loaded, and reaches `target` from `owner`'s position — i.e. a bunker volley
## would actually produce a projectile this tick.
func can_fire_at(owner: Commandable, target: Entity) -> bool:
	if not bunker:
		return false
	for unit: Commandable in _garrisoned:
		if _firing_weapon(unit, owner, target) != null:
			return true
	return false


## The first weapon in `unit`'s inventory that can target `target`, is ready to
## fire, and reaches it from `owner`'s position; null if none qualifies.
func _firing_weapon(unit: Commandable, owner: Commandable, target: Entity) -> Weapon:
	if unit.weapon_inventory == null:
		return null
	var weapon := unit.weapon_inventory.weapon_for_target(target)
	if weapon == null or not weapon.is_ready():
		return null
	if not SU.is_weapon_in_range_at(weapon, owner.global_transform, owner.get_world_3d(), target, owner):
		return null
	return weapon


## Remove `unit` from the active scene tree and store it here.
func garrison(unit: Commandable) -> void:
	_adopt_commander_if_neutral(unit)
	# For a bunker, hoist the unit's weapon inventory onto this garrison's owner
	# so its weapons keep advancing their _physics_process reload timers — an
	# orphaned (off-tree) unit doesn't tick, so otherwise its weapons would never
	# reload or fire. The unit itself still leaves the tree; only its Loadout
	# stays, reparented under the owner.
	var owner_node := get_parent()
	if bunker and owner_node != null and unit.weapon_inventory != null:
		unit.weapon_inventory.reparent(owner_node, false)
	unit.get_parent().remove_child(unit)
	_garrisoned.append(unit)
	_refresh_aggro_range()


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
## garrison owner occupies the terrain grid (has an Structure component) or
## is itself a non-grid entity such as a unit.
func evacuate(a_map: Map) -> void:
	var owner_cmd := get_parent() as Commandable

	if owner_cmd != null and owner_cmd.has_node("Structure"):
		_evacuate_from_structure(owner_cmd, a_map)
	else:
		_evacuate_from_unit(owner_cmd, a_map)

	_garrisoned.clear()
	_revert_adopted_commander(owner_cmd)
	_refresh_aggro_range()

	# If the host landed to accept garrison units, return it to hover altitude.
	if owner_cmd != null and owner_cmd.movement != null \
			and owner_cmd.movement.mode == Movement.Mode.HOVERING:
		owner_cmd.movement.take_off()


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
## Move a garrisoned unit's weapon inventory back under the unit, reversing the
## hoist done in garrison(). Call after the unit has been re-added to the tree.
## A no-op when the Loadout was never moved (non-bunker garrison, or unit had no
## inventory), detected via the Loadout's current parent.
func _restore_loadout(unit: Commandable) -> void:
	var loadout := unit.weapon_inventory
	if loadout != null and loadout.get_parent() != unit:
		loadout.reparent(unit, false)


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
		_restore_loadout(unit)

		if spawn_cell != Vector2i(-1, -1):
			var spawn_xz := a_map.grid_to_world(spawn_cell)
			var height_offset := unit.movement.height_offset() if unit.movement != null else 0.0
			unit.global_position = Vector3(
				spawn_xz.x,
				a_map.terrain_height_at(VU.inXZ(spawn_xz)) + height_offset,
				spawn_xz.z
			)

		unit.update_commands(Command.new(CommandMessage.new(a_map, null, null, dest)))


## Recompute the host's AggroRange radius to cover the widest weapon range among all
## garrisoned units, clamped below by the host's original (pre-garrison) radius.
## On the last evacuation (empty _garrisoned) the original radius is restored.
func _refresh_aggro_range() -> void:
	var owner_cmd := get_parent() as Commandable
	if owner_cmd == null or owner_cmd.aggro_range_shape == null:
		return
	var aggro_shape: Shape3D = owner_cmd.aggro_range_shape.shape
	if aggro_shape == null:
		return
	if _garrisoned.is_empty():
		if _original_aggro_radius >= 0.0:
			_set_shape_radius(aggro_shape, _original_aggro_radius)
			_original_aggro_radius = -1.0
		return
	if _original_aggro_radius < 0.0:
		_original_aggro_radius = _get_shape_radius(aggro_shape)
	var best: float = _original_aggro_radius
	for unit: Commandable in _garrisoned:
		if unit.weapon_inventory == null:
			continue
		for child in unit.weapon_inventory.get_children():
			var weapon: Weapon = child as Weapon
			if weapon == null:
				continue
			if weapon.attack_range_shape_ground != null and weapon.attack_range_shape_ground.shape != null:
				best = maxf(best, _get_shape_radius(weapon.attack_range_shape_ground.shape))
			if weapon.attack_range_shape_air != null and weapon.attack_range_shape_air.shape != null:
				best = maxf(best, _get_shape_radius(weapon.attack_range_shape_air.shape))
	_set_shape_radius(aggro_shape, best)


static func _get_shape_radius(shape: Shape3D) -> float:
	if shape is SphereShape3D:
		return (shape as SphereShape3D).radius
	if shape is CylinderShape3D:
		return (shape as CylinderShape3D).radius
	return 0.0


static func _set_shape_radius(shape: Shape3D, radius: float) -> void:
	if shape is SphereShape3D:
		(shape as SphereShape3D).radius = radius
	elif shape is CylinderShape3D:
		(shape as CylinderShape3D).radius = radius


## Safety net: free any garrisoned units that are still orphaned when this component
## is freed (i.e. when the host dies and neither evacuate() nor kill_occupants() had
## already cleared them). In-tree units are left untouched.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for unit: Commandable in _garrisoned:
			if is_instance_valid(unit) and not unit.is_inside_tree():
				unit.free()


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
		_restore_loadout(unit)
		unit.global_position = spawn_pos

		if a_map != null:
			unit.update_commands(Command.new(CommandMessage.new(a_map, null, null, spawn_pos)))
#endregion
