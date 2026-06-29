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
func _deploy_all_forces() -> void:
	var start_points: Array[Node3D] = _start_points()
	if start_points.size() < player_slots.size():
		push_error("Skirmish: %d player slots but only %d '%s' start-point nodes in the scene" % [
			player_slots.size(), start_points.size(), START_POINT_GROUP
		])
	for i: int in player_slots.size():
		if i >= start_points.size():
			break
		_spawn_slot_force(player_slots[i], VU.inXZ(start_points[i].global_position))
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


## Deploy one slot's faction-defined opening force, centred on `origin` (world XZ).
## Reuses the Faction instance the slot's Commander already built in _instance_faction
## (no need to re-instantiate the faction scene). No-op for a slot with no commander
## or no faction (e.g. a commander left on player.tscn's default with nothing authored).
func _spawn_slot_force(slot: PlayerSlot, origin: Vector2) -> void:
	var commander: Commander = slot.commander
	if commander == null or commander.faction == null:
		return
	var faction: Faction = commander.faction

	var entities: Array = []
	if faction.starting_structure != null:
		entities.append(faction.starting_structure.instantiate())
	for unit_scene: PackedScene in faction.starting_units:
		if unit_scene != null:
			entities.append(unit_scene.instantiate())

	if entities.is_empty():
		return

	# add_entities registers any Structure on the grid at `origin` and scatters the
	# units onto nearby navmesh, calling initialize(map, commander) on each so the
	# entity enters the tree under its commander with ownership set.
	map.add_entities(entities, origin, commander)
