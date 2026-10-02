extends GutTest

## Where a faction's opening units stand: the pure geometry behind StartingFormation.
##
## All of it runs with no map, no navmesh and no scenario — reading slots out of a scene,
## pointing the formation at the middle of the board, and turning it to face that way. What
## is NOT here is the deployment itself (Skirmish + Map.add_entities), which needs a live
## navmesh; the snapping that corrects an authored slot over a cliff belongs to that half.

const DISTANCE: float = 3.0


## A formation scene stand-in: plain Node3Ds at the given XZ offsets, in order.
func _formation(a_offsets: Array) -> Node3D:
	var root := Node3D.new()
	for offset: Vector2 in a_offsets:
		var slot := Node3D.new()
		slot.position = Vector3(offset.x, 0.0, offset.y)
		root.add_child(slot)
	add_child_autofree(root)
	return root


#region Reading the slots
func test_slots_are_read_in_child_order() -> void:
	var offsets: Array[Vector2] = StartingFormation.offsets_from(
		_formation([Vector2(0, -1), Vector2(-2, 1), Vector2(2, 1)])
	)
	assert_eq(offsets, [Vector2(0, -1), Vector2(-2, 1), Vector2(2, 1)] as Array[Vector2])


func test_height_is_discarded() -> void:
	var root := _formation([Vector2(1, 2)])
	(root.get_child(0) as Node3D).position.y = 17.0
	assert_eq(StartingFormation.offsets_from(root), [Vector2(1, 2)] as Array[Vector2])


func test_a_non_spatial_child_is_not_a_slot() -> void:
	var root := _formation([Vector2(1, 0)])
	root.add_child(Node.new())
	assert_eq(StartingFormation.offsets_from(root).size(), 1)


func test_nothing_to_read_is_no_formation() -> void:
	assert_eq(StartingFormation.offsets_from(null), [] as Array[Vector2])
	assert_eq(StartingFormation.offsets_from(autofree(Node3D.new())), [] as Array[Vector2])


#endregion


#region Facing the middle
func test_the_heading_points_at_the_centre() -> void:
	assert_eq(StartingFormation.heading_toward(Vector2(-10, 0), Vector2.ZERO), Vector2.RIGHT)
	assert_eq(StartingFormation.heading_toward(Vector2(0, 40), Vector2.ZERO), Vector2.UP)


func test_the_heading_is_a_unit_vector() -> void:
	assert_almost_eq(
		StartingFormation.heading_toward(Vector2(-30, 30), Vector2.ZERO).length(), 1.0, 0.0001
	)


## A start point ON the centre names no direction, so the authored facing stands — which is
## the due-north deployment this replaced.
func test_a_start_point_at_the_centre_keeps_the_authored_facing() -> void:
	assert_eq(
		StartingFormation.heading_toward(Vector2.ZERO, Vector2.ZERO),
		StartingFormation.AUTHORED_FACING
	)


#endregion


#region Anchoring
func test_the_anchor_is_the_stated_distance_inward() -> void:
	var anchor: Vector2 = StartingFormation.anchor(Vector2(-10, 0), Vector2.ZERO, DISTANCE)
	assert_eq(anchor, Vector2(-7, 0))


func test_the_anchor_moves_toward_the_centre_from_any_corner() -> void:
	var center := Vector2(50, 50)
	for corner: Vector2 in [Vector2(0, 0), Vector2(100, 0), Vector2(0, 100), Vector2(100, 100)]:
		var anchor: Vector2 = StartingFormation.anchor(corner, center, DISTANCE)
		assert_lt(
			anchor.distance_to(center),
			corner.distance_to(center),
			"deploying from %s must move inward" % corner
		)
		assert_almost_eq(corner.distance_to(anchor), DISTANCE, 0.0001)


#endregion


#region Rotating the whole arrangement
## Authored facing already points at the centre: nothing turns, and every slot is its raw
## offset from the anchor.
func test_an_unrotated_formation_keeps_its_offsets() -> void:
	var points: Array[Vector2] = StartingFormation.world_points(
		[Vector2(0, -1), Vector2(2, 1)] as Array[Vector2], Vector2(0, 10), Vector2.ZERO, DISTANCE
	)
	assert_eq(points[0], Vector2(0, 6))
	assert_eq(points[1], Vector2(2, 8))


## Turned a quarter: the slot the author put in FRONT still ends up between the base and the
## middle of the map, whichever edge the base is on.
func test_the_leading_slot_leads_whichever_way_the_formation_faces() -> void:
	var center := Vector2.ZERO
	for start: Vector2 in [Vector2(0, 10), Vector2(0, -10), Vector2(10, 0), Vector2(-10, 0)]:
		var points: Array[Vector2] = StartingFormation.world_points(
			[Vector2(0, -1)] as Array[Vector2], start, center, DISTANCE
		)
		assert_almost_eq(
			points[0].distance_to(center),
			10.0 - DISTANCE - 1.0,
			0.0001,
			"the leader stands one unit further in than the anchor, from %s" % start
		)


func test_rotation_is_rigid() -> void:
	var offsets: Array[Vector2] = [Vector2(0, -1), Vector2(-2, 1), Vector2(2, 1)]
	var start := Vector2(-30, 17)
	var center := Vector2(4, -8)
	var points: Array[Vector2] = StartingFormation.world_points(offsets, start, center, DISTANCE)
	var anchor: Vector2 = StartingFormation.anchor(start, center, DISTANCE)
	for i: int in offsets.size():
		assert_almost_eq(
			points[i].distance_to(anchor),
			offsets[i].length(),
			0.0001,
			"slot %d keeps its distance from the formation origin" % i
		)
	assert_almost_eq(
		points[1].distance_to(points[2]),
		offsets[1].distance_to(offsets[2]),
		0.0001,
		"and its neighbours keep theirs"
	)


func test_one_point_per_slot() -> void:
	assert_eq(
		(
			StartingFormation
			. world_points([] as Array[Vector2], Vector2(1, 1), Vector2.ZERO, DISTANCE)
			. size()
		),
		0
	)
	assert_eq(
		(
			StartingFormation
			. world_points(
				[Vector2.ZERO, Vector2.ONE] as Array[Vector2], Vector2(1, 1), Vector2.ZERO, DISTANCE
			)
			. size()
		),
		2
	)


#endregion


#region What the shipped factions author
## The assert Skirmish makes at deploy time, made here instead so a mismatched formation
## fails the suite rather than a match.
func test_every_faction_formation_has_one_slot_per_starting_unit() -> void:
	for path: String in [
		"res://scenes/factions/anarchical.tscn",
		"res://scenes/factions/colonial.tscn",
		"res://scenes/factions/libertarian.tscn",
		"res://scenes/factions/technocratic.tscn",
	]:
		var faction: Faction = (load(path) as PackedScene).instantiate()
		autofree(faction)
		assert_not_null(faction.starting_formation, "%s authors a starting formation" % path)
		if faction.starting_formation == null:
			continue
		var slots: Node = faction.starting_formation.instantiate()
		assert_eq(
			StartingFormation.offsets_from(slots).size(),
			faction.starting_units.size(),
			"%s: one slot per starting unit" % path
		)
		slots.free()


#endregion


#region Clearance is measured from the footprint edge
## The gap in front of a base must not depend on how big that base happens to be — see
## StartingFormation.DISTANCE_CELLS. These pin the slab geometry that makes that true.
func test_extent_is_zero_without_a_footprint() -> void:
	# The fallback every caller gets when it has no Structure to ask: measure from the centre,
	# exactly as this did before footprints were considered.
	assert_eq(StartingFormation.extent_toward(Vector2.ZERO, Vector2.RIGHT), 0.0)


func test_extent_along_an_axis_is_that_half_extent() -> void:
	var half := Vector2(2.5, 1.5)
	assert_almost_eq(StartingFormation.extent_toward(half, Vector2.RIGHT), 2.5, 0.0001)
	assert_almost_eq(StartingFormation.extent_toward(half, Vector2.DOWN), 1.5, 0.0001)
	# Sign of the heading cannot matter: the rectangle is symmetric about its centre.
	assert_almost_eq(StartingFormation.extent_toward(half, Vector2.LEFT), 2.5, 0.0001)


func test_a_diagonal_leaves_through_the_nearer_side_not_the_corner() -> void:
	# The slab test's whole content. For a 2x1 half-extent at 45 degrees, the SHORT axis is
	# reached first, so the exit is at 1.0/sin(45) — not the corner distance.
	var half := Vector2(2.0, 1.0)
	var diagonal: Vector2 = Vector2(1.0, 1.0).normalized()
	assert_almost_eq(StartingFormation.extent_toward(half, diagonal), 1.0 / diagonal.y, 0.0001)
	assert_lt(
		StartingFormation.extent_toward(half, diagonal),
		half.length(),
		"leaving through a side is nearer than reaching the corner"
	)


func test_half_extents_come_from_the_cell_footprint() -> void:
	assert_eq(StartingFormation.half_extents_of(Vector2i(5, 3), 1.0), Vector2(2.5, 1.5))
	assert_eq(StartingFormation.half_extents_of(Vector2i(1, 1), 2.0), Vector2(1.0, 1.0))


func test_a_bigger_base_pushes_the_formation_further_out() -> void:
	# The bug this change fixes: with a centre-relative gap, a 5x5 command centre left its
	# units almost against the wall while a 1x1 left them two tiles clear.
	var start := Vector2(10.0, 10.0)
	var center := Vector2(10.0, 0.0)
	var small: Vector2 = StartingFormation.anchor(
		start, center, 3.0, StartingFormation.half_extents_of(Vector2i(1, 1), 1.0)
	)
	var large: Vector2 = StartingFormation.anchor(
		start, center, 3.0, StartingFormation.half_extents_of(Vector2i(5, 5), 1.0)
	)
	assert_gt(
		start.distance_to(large),
		start.distance_to(small),
		"the larger footprint stands its formation further from the centre"
	)
	assert_almost_eq(
		start.distance_to(large) - start.distance_to(small),
		2.0,
		0.0001,
		"and further by exactly the difference in half-extent"
	)


func test_the_clearance_is_the_same_daylight_whatever_the_base() -> void:
	# Stated the way the rule is stated: measured from the EDGE, both bases leave 3.0.
	var start := Vector2(0.0, 0.0)
	var center := Vector2(0.0, -10.0)
	for dims: Vector2i in [Vector2i(1, 1), Vector2i(3, 3), Vector2i(5, 5)]:
		var half: Vector2 = StartingFormation.half_extents_of(dims, 1.0)
		var origin: Vector2 = StartingFormation.anchor(start, center, 3.0, half)
		assert_almost_eq(
			start.distance_to(origin) - half.y,
			3.0,
			0.0001,
			"a %s base leaves 3.0 clear of its own edge" % dims
		)


func test_world_points_carry_the_footprint_standoff() -> void:
	# The formation as a whole moves out with the anchor; the slot offsets are unchanged.
	var offsets: Array[Vector2] = [Vector2.ZERO, Vector2(1.0, 0.0)]
	var start := Vector2.ZERO
	var center := Vector2(0.0, -10.0)
	var half: Vector2 = StartingFormation.half_extents_of(Vector2i(4, 4), 1.0)
	var centred: Array[Vector2] = StartingFormation.world_points(offsets, start, center, 3.0)
	var edged: Array[Vector2] = StartingFormation.world_points(offsets, start, center, 3.0, half)
	assert_eq(centred.size(), edged.size())
	for i: int in offsets.size():
		assert_almost_eq(
			centred[i].distance_to(edged[i]),
			half.y,
			0.0001,
			"every slot shifts by the same standoff"
		)
#endregion
