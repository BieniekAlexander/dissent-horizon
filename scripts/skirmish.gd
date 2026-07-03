class_name Skirmish
extends Scenario

## A Skirmish is a Scenario whose opening forces are built at runtime from each
## player slot's faction, rather than being placed in the scene tree by hand. This
## keeps the .tscn faction-agnostic: swap a slot's faction and the right structure +
## units deploy automatically, with no per-faction copies of the map.
##
## Deploy positions come from marker nodes authored in the scene (in the
## START_POINT_GROUP group), one per player slot, mapped to slots by sorted name
## order — so the map author places the starting positions and the script just fills
## them. For each slot it spawns, at that slot's start point:
##   - the faction's starting_structure (the HQ/base), and
##   - the faction's starting_units, arranged around it.
## Ownership is handed straight to the slot's commander via Map.add_entities, which
## also registers the structure on the grid and places units on the navmesh.
##
## Neutral/map features (deposits, mines, shelters, terrain) stay authored in the
## scene — they aren't faction forces and aren't this class's concern.

## Scene nodes (Node3D) in this group mark where each player slot deploys. The scene
## should hold at least player_slots.size() of them; they're matched to slots by
## sorted name order (e.g. "StartPoint1" → slot 0, "StartPoint2" → slot 1).
const START_POINT_GROUP := "start_position"


func _spawn_initial_entities() -> void:
	# Unit placement (Map.add_entities → get_nonoverlapping_points) queries the
	# navigation map, which the NavigationServer has NOT synchronized yet during
	# _ready — querying it now yields zero points and the units never spawn. Gate on
	# the NavManager's one-shot navmesh_ready signal so the opening force deploys onto
	# a real, synced surface. (Structures alone wouldn't need this; units do.)
	if map.nav_manager.is_ready():
		_deploy_all_forces()
	else:
		map.nav_manager.navmesh_ready.connect(_deploy_all_forces, CONNECT_ONE_SHOT)


## Spawn every slot's opening force at its matching start-point node, then re-frame
## the human player's camera on it (a no-op in spectator sessions). Runs immediately
## if the navmesh is already built, otherwise once navmesh_ready fires — so it can
## land a frame or two after _ready.
##
## Structures are spawned for every slot BEFORE any units: placing a structure
## registers its footprint on the grid synchronously, but the navmesh rebuild
## that excludes those cells (and the collision layer that would otherwise let
## the unit scatter step see the structure as an obstacle) only lands once the
## NavigationServer syncs it — see NavManager.await_excluded. Scattering units in
## the same call as their slot's structure would race that rebuild and could
## place a unit inside the structure's footprint. Waiting here lets
## Map.add_entities' get_nonoverlapping_points see every just-placed structure
## as an obstacle before it picks unit positions.
func _deploy_all_forces() -> void:
	var start_points: Array[Node3D] = _start_points()
	if start_points.size() < player_slots.size():
		push_error("Skirmish: %d player slots but only %d '%s' start-point nodes in the scene" % [
			player_slots.size(), start_points.size(), START_POINT_GROUP
		])

	# Index i -> the Commandable Structure just placed for player_slots[i], or null
	# (no structure / no commander for that slot). _spawn_slot_units uses this to
	# seed unit scattering off the structure's footprint instead of its own centre.
	var structures: Array = []
	var footprint_probes: Array[Vector3] = []
	for i: int in player_slots.size():
		if i >= start_points.size():
			structures.append(null)
			continue
		var structure: Commandable = _spawn_slot_structure(player_slots[i], VU.inXZ(start_points[i].global_position))
		structures.append(structure)
		if structure != null:
			for cell: Vector2i in map.structure_cell_map.get(structure, []):
				footprint_probes.append(map.grid_to_world(cell))

	# Force the cells_changed → navmesh rebuild triggered by the structures above
	# to actually sync before scattering units onto the navmesh — is_ready()/
	# navmesh_ready only cover the very first build; later rebuilds otherwise
	# just ride the normal (unforced) async sync, which isn't guaranteed to have
	# landed by the next line.
	await map.nav_manager.await_excluded(footprint_probes)

	for i: int in player_slots.size():
		if i >= start_points.size():
			break
		_spawn_slot_units(player_slots[i], VU.inXZ(start_points[i].global_position), structures[i])
	_center_player_camera_on_starting_entities()


## The scene's start-point marker nodes, sorted by name so the slot→point mapping is
## deterministic (slot order ↔ "StartPoint1", "StartPoint2", …) regardless of the
## order the group reports.
func _start_points() -> Array[Node3D]:
	var points: Array[Node3D] = []
	for node: Node in get_tree().get_nodes_in_group(START_POINT_GROUP):
		if node is Node3D:
			points.append(node)
	# Compare as String, not StringName — StringName's < is pointer/hash order, not
	# lexicographic, which would make the slot→point mapping effectively arbitrary.
	points.sort_custom(func(a: Node3D, b: Node3D) -> bool: return String(a.name) < String(b.name))
	return points


## Spawn one slot's faction-defined starting structure (the HQ/base), centred on
## `origin` (world XZ). Reuses the Faction instance the slot's Commander already
## built in _instance_faction (no need to re-instantiate the faction scene). No-op
## (returns null) for a slot with no commander/faction, or a faction with no
## starting structure. Returns the spawned Commandable so _spawn_slot_units can
## seed unit scattering off its footprint.
func _spawn_slot_structure(slot: PlayerSlot, origin: Vector2) -> Commandable:
	var commander: Commander = slot.commander
	if commander == null or commander.faction == null:
		return null
	var faction: Faction = commander.faction
	if faction.starting_structure == null:
		return null

	var structure: Commandable = faction.starting_structure.instantiate()
	# add_entities registers the Structure on the grid at `origin`, calling
	# initialize(map, commander) so it enters the tree under its commander with
	# ownership set.
	map.add_entities([structure], origin, commander)
	return structure


## Spawn one slot's faction-defined starting units, arranged around `structure`'s
## footprint (falling back to `origin` if the slot has no structure). Called only
## after every slot's starting structure has been placed (see _deploy_all_forces)
## so the units scatter onto navmesh that already excludes the structures'
## footprints.
func _spawn_slot_units(slot: PlayerSlot, origin: Vector2, structure: Commandable) -> void:
	var commander: Commander = slot.commander
	if commander == null or commander.faction == null:
		return
	var faction: Faction = commander.faction

	var units: Array = []
	for unit_scene: PackedScene in faction.starting_units:
		if unit_scene != null:
			units.append(unit_scene.instantiate())

	if units.is_empty():
		return

	# SU.get_nonoverlapping_points seeds its scatter search AT the point it's given
	# and only grows outward from points that land on the navmesh — so seeding it
	# with `origin` (the structure's own centre, now off-navmesh) finds nothing and
	# every unit falls back to that same off-navmesh point. Seed from the nearest
	# footprint-adjacent cell instead, which is guaranteed to be on-navmesh.
	var scatter_origin: Vector2 = origin
	if structure != null:
		var adjacent_cell: Vector2i = SU.nearest_footprint_adjacent_cell(
			Vector3(origin.x, map.terrain_height_at(origin), origin.y), structure, map
		)
		if adjacent_cell != Vector2i(-1, -1):
			scatter_origin = VU.inXZ(map.grid_to_world(adjacent_cell))

	# add_entities scatters the units onto nearby navmesh (get_nonoverlapping_points),
	# calling initialize(map, commander) on each so the entity enters the tree under
	# its commander with ownership set.
	map.add_entities(units, scatter_origin, commander)
