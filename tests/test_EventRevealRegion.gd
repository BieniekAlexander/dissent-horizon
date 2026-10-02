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


func _vision_shape(a_scout: Commandable) -> CylinderShape3D:
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
	assert_eq(_event._target_points(_manager)[0], VU.inXZ(here.global_position))


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
	var scout: Commandable = FakePieces.unit(SCOUT)
	add_child_autofree(scout)
	_event._resize_vision(scout)
	assert_almost_eq(_vision_shape(scout).radius, 10.0, 0.001)


func test_resizing_one_area_does_not_resize_the_scout_scene() -> void:
	# A PackedScene's sub-resources are SHARED across its instances, so writing the radius in
	# place would resize the Radar Scan sanction's scouts and every other reveal along with
	# this one. _resize_vision duplicates the shape first.
	# Two instances sharing ONE shape resource, as two instances of one scene do.
	var shared := CylinderShape3D.new()
	shared.radius = 12.0
	var original: float = shared.radius
	var resized: Commandable = FakePieces.unit(SCOUT)
	(resized.get_node("VisionRange") as CollisionShape3D).shape = shared
	var untouched: Commandable = FakePieces.unit(SCOUT)
	(untouched.get_node("VisionRange") as CollisionShape3D).shape = shared

	_event.radius = 99.0
	add_child_autofree(resized)
	_event._resize_vision(resized)
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
