class_name Skirmish
extends Scenario

## A Skirmish is a Scenario whose opening forces are built at runtime from each
## player slot's faction, rather than being placed in the scene tree by hand. This
## keeps the .tscn faction-agnostic: swap a slot's faction and the right units
## deploy automatically, with no per-faction copies of the map.
##
## Deploy positions come from marker nodes authored in the scene (in the
## START_POINT_GROUP group), one per player slot, mapped to slots by sorted name
## order — so the map author places the starting positions and the script just fills
## them. For each slot it spawns, at that slot's start point, the faction's starting_units, in
## its starting_formation three tiles toward the middle of the map (or scattered when it
## declares none). No structure is spawned: every Skirmish deploys by drop, so the slot holds a
## command-centre drop instead (Deployment; starting-formations.md §Deferred deployment).
## Ownership is handed straight to the slot's commander via Map.add_entities, which places
## the units on the navmesh.
##
## Every other neutral/map feature (extraction sites, shelters, terrain) stays authored in the
## scene — they aren't faction forces and aren't this class's concern.

## Scene nodes (Node3D) in this group mark where each player slot deploys — authored in the
## MAP, since where a match can start is a fact about the map rather than the scenario.
##
## **A scenario may have no more slots than its map has start points**, and matching is by
## sorted name order ("StartPoint1" → slot 0, "StartPoint2" → slot 1). Fewer slots than points
## is the normal case: the first N points are used and the rest of the map's starts go unplayed,
## which is how one map serves a two-player skirmish and a four-player one.
const START_POINT_GROUP := "start_position"


## Every Skirmish deploys by drop; it is the reference game for tuning the competitive match.
func uses_deferred_deployment() -> bool:
	return true


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


## Spawn every slot's starting units at its matching start-point node, then re-frame the human
## player's camera on them (a no-op in spectator sessions). Runs immediately if the navmesh is
## already built, otherwise once navmesh_ready fires — so it can land a frame or two after _ready.
func _deploy_all_forces() -> void:
	var start_points: Array[Node3D] = _start_points()
	if start_points.size() < player_slots.size():
		push_error(
			(
				(
					"Skirmish: %d player slots but the map has only %d start points ('%s'). "
					+ "A scenario may not have more slots than its map has starts; the slots past %d "
					+ "deploy nothing."
				)
				% [player_slots.size(), start_points.size(), START_POINT_GROUP, start_points.size()]
			)
		)
	for i: int in mini(player_slots.size(), start_points.size()):
		_spawn_slot_units(player_slots[i], VU.inXZ(start_points[i].global_position))
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


## Spawn one slot's faction-defined starting units at `a_origin`, in its formation when it
## declares one, scattered onto the navmesh around the start point when it does not.
func _spawn_slot_units(a_slot: PlayerSlot, a_origin: Vector2) -> void:
	var commander: Commander = a_slot.commander
	if commander == null or commander.faction == null:
		return
	var faction: Faction = commander.faction

	var units: Array = []
	for unit_scene: PackedScene in faction.starting_units:
		if unit_scene != null:
			units.append(unit_scene.instantiate())

	if units.is_empty():
		return

	# An authored formation replaces the scatter outright: the units stand where the faction
	# says, three tiles into the map from the start point, facing it.
	var formation_points: Array[Vector2] = _formation_points(faction, a_origin, units.size())

	# add_entities scatters the units onto nearby navmesh (get_nonoverlapping_points) when no
	# formation was given, calling initialize(map, commander) on each so the entity enters the
	# tree under its commander with ownership set. Formation points are snapped to navigable
	# ground the same way, so an authored slot over a cliff is corrected rather than obeyed.
	var seed_point: Vector2 = formation_points[0] if not formation_points.is_empty() else a_origin
	map.add_entities(units, seed_point, commander, formation_points)


## Where this faction's `a_count` starting units stand, or EMPTY for "scatter them".
##
## Empty covers both no formation authored and a formation whose slot count disagrees with
## the faction's unit list. The mismatch is an authoring error and says so twice: an assert,
## which stops a debug run at the fault, and a push_error plus the scatter fallback, so a
## release build deploys a usable force rather than none.
func _formation_points(a_faction: Faction, a_origin: Vector2, a_count: int) -> Array[Vector2]:
	if a_faction.starting_formation == null:
		return []
	var slots: Node = a_faction.starting_formation.instantiate()
	var offsets: Array[Vector2] = StartingFormation.offsets_from(slots)
	slots.free()
	assert(
		offsets.size() == a_count,
		(
			"Skirmish: %s's starting_formation has %d slots for %d starting units"
			% [a_faction.faction_name, offsets.size(), a_count]
		)
	)
	if offsets.size() != a_count:
		push_error(
			(
				"Skirmish: %s's starting_formation has %d slots for %d starting units"
				% [a_faction.faction_name, offsets.size(), a_count]
			)
		)
		return []
	var area: PlayArea = map.play_area()
	# No declared play area leaves no middle to face; the formation then keeps its authored
	# heading, which is the direction the old scatter deployed in anyway.
	var center: Vector2 = area.center if area != null else a_origin
	return StartingFormation.world_points(
		offsets, a_origin, center, StartingFormation.DISTANCE_CELLS * Map.CELL_SIZE, Vector2.ZERO
	)
