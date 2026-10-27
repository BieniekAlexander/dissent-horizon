extends GutTest

## Tests for EventRevealRegion — opening a piece of the map, either by marking it explored or
## by clearing the fog over it, at a point or over a group.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_EventRevealRegion.gd -gexit
##
## These check what the event PRODUCES (vision sources, where, how big, for how long) rather
## than the resulting fog texture, which needs a Map and a physics frame to rebuild. The fog
## itself is exercised by test_ScoutVision.

## A watcher: a fake piece with a vision cylinder.
const SCOUT: Dictionary = {"vision": 12.0}
const GROUP: StringName = &"test_reveal_targets"

var _event: EventRevealRegion
var _manager: ScenarioTriggerManager


func before_each() -> void:
	# The event reads the group through the manager's tree, as the other events do.
	_manager = ScenarioTriggerManager.new()
	add_child_autofree(_manager)
	assert_push_warning("expected parent to be Scenario")
	_event = EventRevealRegion.new()
	_event.clears_fog = true
	_event.radius = 10.0
	add_child_autofree(_event)


func after_each() -> void:
	if _manager.simulation_clock != null:
		_manager.simulation_clock.clear()
	get_tree().paused = false


## A Node3D in the target group, at `xz`.
func _target(a_xz: Vector2) -> Node3D:
	var node := Node3D.new()
	node.add_to_group(GROUP)
	add_child_autofree(node)
	node.global_position = Vector3(a_xz.x, 0.0, a_xz.y)
	return node


func _vision_shape(a_scout: Actor) -> CylinderShape3D:
	return (a_scout.get_node("VisionRange") as CollisionShape3D).shape as CylinderShape3D


# --- Targeting ------------------------------------------------------------------


func test_a_group_reveals_one_area_per_member() -> void:
	_target(Vector2(10.0, 0.0))
	_target(Vector2(-30.0, 25.0))
	_target(Vector2(0.0, -40.0))
	_event.target_group = GROUP
	assert_eq(_event._target_points(_manager).size(), 3, "one reveal per member")


func test_the_areas_land_on_the_members() -> void:
	var here := _target(Vector2(12.0, -34.0))
	_event.target_group = GROUP
	assert_eq(_event._target_points(_manager)[0], VU.in_xz(here.global_position))


func test_no_group_reveals_at_the_events_own_position() -> void:
	# So the event is still useful on its own, pointed at a place rather than at a set.
	_event.global_position = Vector3(7.0, 3.0, -9.0)
	var points: Array[Vector2] = _event._target_points(_manager)
	assert_eq(points, [Vector2(7.0, -9.0)] as Array[Vector2], "its own XZ, height ignored")


func test_non_spatial_group_members_are_skipped() -> void:
	# A group may hold anything; only something with a position can be revealed.
	var plain := Node.new()
	plain.add_to_group(GROUP)
	add_child_autofree(plain)
	_target(Vector2(5.0, 5.0))
	_event.target_group = GROUP
	assert_eq(_event._target_points(_manager).size(), 1, "only the one that has somewhere to be")


func test_an_empty_group_reveals_nothing() -> void:
	_event.target_group = &"test_nobody_is_in_this_group"
	assert_eq(_event._target_points(_manager), [], "and no fallback to the event's own position")


# --- The revealed area ----------------------------------------------------------


func test_the_area_is_a_cylinder_of_the_configured_radius() -> void:
	_event.radius = 10.0
	var scout: Actor = FakePieces.unit(SCOUT)
	add_child_autofree(scout)
	EventRevealRegion._resize_vision(scout, _event.radius)
	assert_almost_eq(_vision_shape(scout).radius, 10.0, 0.001)


func test_a_reveal_drone_is_neither_drawn_nor_a_target() -> void:
	var drone: Actor = FakePieces.unit(
		{"vision": 12.0, "hp": 50.0, "aerial": true, "mesh": true, "status_visuals": true}
	)
	drone.add_child(AltitudeIndicator.new())
	drone.get_child(-1).name = "AltitudeIndicator"
	EventRevealRegion._make_unseen(drone)
	add_child_autofree(drone)
	assert_null(drone.get_node_or_null("AltitudeIndicator"), "no marker under it")
	assert_false((drone.get_node("MeshVisual") as Node3D).visible, "no model")
	assert_false((drone.get_node("StatusVisuals") as Node3D).visible, "no badges")
	assert_false(drone.is_attackable(), "nothing to shoot")
	assert_not_null(drone.get_node_or_null("VisionRange"), "but it still sees")


func test_resizing_one_area_does_not_resize_the_scout_scene() -> void:
	# A PackedScene's sub-resources are SHARED across its instances, so writing the radius in
	# place would resize the Radar Scan sanction's scouts and every other reveal along with
	# this one. _resize_vision duplicates the shape first.
	# Two instances sharing ONE shape resource, as two instances of one scene do.
	var shared := CylinderShape3D.new()
	shared.radius = 12.0
	var original: float = shared.radius
	var resized: Actor = FakePieces.unit(SCOUT)
	(resized.get_node("VisionRange") as CollisionShape3D).shape = shared
	var untouched: Actor = FakePieces.unit(SCOUT)
	(untouched.get_node("VisionRange") as CollisionShape3D).shape = shared

	_event.radius = 99.0
	add_child_autofree(resized)
	EventRevealRegion._resize_vision(resized, _event.radius)
	add_child_autofree(untouched)
	assert_almost_eq(_vision_shape(resized).radius, 99.0, 0.001, "this one grew")
	assert_almost_eq(_vision_shape(untouched).radius, original, 0.001, "the scene did not")


func test_marking_explored_is_the_default() -> void:
	# The cheap, instantaneous mode: no node created, nothing persists. Clearing the fog is
	# the opt-in, because it spawns a standing vision source.
	var fresh := EventRevealRegion.new()
	autofree(fresh)
	assert_false(fresh.clears_fog)


func test_the_reveal_is_permanent_by_default() -> void:
	# Radar Scan is the temporary version; a mission showing where its objectives are wants
	# the reveal to stay. A negative lifespan attaches no Lifespan at all.
	assert_lt(_event.lifespan_seconds, 0.0)


func test_the_reveal_belongs_to_the_player_by_default() -> void:
	# The revealed area is only visible to its owner, so a mission reveal is the human's.
	assert_eq(_event.commander_id, 1)


# --- A turned box ---------------------------------------------------------------


func _turned_region(a_size: Vector2, a_yaw: float) -> CollisionShape3D:
	var region := CollisionShape3D.new()
	region.name = "Region"
	var box := BoxShape3D.new()
	box.size = Vector3(a_size.x, 4.0, a_size.y)
	region.shape = box
	_event.add_child(region)
	region.transform = Transform3D(VU.with_yaw(Basis(), a_yaw), Vector3(3.0, 0.0, -2.0))
	return region


func test_a_region_is_seen_by_one_piece_turned_as_it_is() -> void:
	var region: CollisionShape3D = _turned_region(Vector2(60.0, 20.0), 0.3)
	var scout: Actor = autofree(FakePieces.unit(SCOUT))
	EventRevealRegion._see_region(scout, region)
	var vision := scout.get_node("VisionRange") as CollisionShape3D
	assert_eq(vision.shape, region.shape, "the region's own shape")
	assert_almost_eq(
		vision.transform.basis.x, region.global_transform.basis.x, Vector3.ONE * 1e-6, "turned"
	)


func test_cover_points_hold_a_turned_region() -> void:
	var shape := HighlightShape.rect(Vector2(3.0, -2.0), Vector2(20.0, 4.0), 0.3)
	var points: Array[Vector2] = EventRevealRegion.cover_points(shape, 2.0)
	for corner: Vector2 in shape.outline():
		var nearest: float = INF
		for point: Vector2 in points:
			nearest = minf(nearest, point.distance_to(corner))
		assert_lt(nearest, 0.01, "a circle on corner %s" % corner)
