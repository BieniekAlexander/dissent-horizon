extends GutTest

## A NAVMESH CHANGE RE-PLANS ONLY THE UNITS WHOSE PATH IT CROSSES.
##
## Run with:
## godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_NavChangeReplanning.gd -gexit
##
## NavigationAgent3D re-plans whenever the navigation map changes, and every structure placed or
## destroyed changes it, so every moving unit used to re-plan in the same tick. NavManager now
## records each rebuild as a NavChange, marked landed once path queries can see it, and Movement
## re-plans only when a landed change crosses the rest of its path — or, for a path that stops
## short of its target, when a change lands around the target. Why:
## gdd/systems/terrain-and-navigation/navigation-and-pathing.md §Re-planning after a navmesh
## change.
##
## The live tests drive a real NavManager on a flat fixture map, like test_NavChunks.

const W: int = 3 * NavManager.CHUNK_SIZE_CELLS + 1  # corners; one fewer cells per side
const MAX_READY_FRAMES: int = 120
## Ticks to wait for a change to land; measured at ~5 on the skirmish map.
const MAX_LANDING_FRAMES: int = 60
const UNIT_RADIUS: float = 0.3


## A Movement that counts its own path queries.
class CountingMovement:
	extends Movement
	var queries: int = 0

	func _query_path(a_origin: Vector3) -> void:
		queries += 1
		super(a_origin)


## A Map over the fixture grid: world XZ to continuous grid coordinates, which is all the
## straight-line test asks of it. Never enters the tree.
class FixtureMap:
	extends Map
	var half: float

	func world_to_grid_point(a_world_xz: Vector2) -> Vector2:
		return a_world_xz + Vector2(half, half)


var _grid: TerrainGrid
var _nav: NavManager


func _make_nav() -> void:
	var shape := HeightMapShape3D.new()
	shape.map_width = W
	shape.map_depth = W
	var data := PackedFloat32Array()
	data.resize(W * W)
	shape.map_data = data
	var body := StaticBody3D.new()
	add_child_autofree(body)
	_grid = TerrainGrid.new()
	_grid.height_map = shape
	_grid.terrain_body = body
	add_child_autofree(_grid)
	var region := NavigationRegion3D.new()
	add_child_autofree(region)
	_nav = NavManager.new()
	_nav.navigation_region = region
	_nav.terrain_grid = _grid
	add_child_autofree(_nav)
	for _i: int in MAX_READY_FRAMES:
		if _nav.is_ready():
			break
		await get_tree().physics_frame
	# The fixture's own early rebuilds must have landed too, or one landing later would
	# legitimately re-plan a unit and be mistaken for the change under test.
	for _i: int in MAX_LANDING_FRAMES:
		if _nav.landed_serial() == _nav._next_change_serial - 1:
			break
		await get_tree().physics_frame


## World position of the centre of cell (x, z) on the fixture map.
func _cell_world(a_x: int, a_z: int) -> Vector3:
	var half: float = (W - 1) * 0.5
	return Vector3(a_x + 0.5 - half, 0.0, a_z + 0.5 - half)


## A ground unit at cell `a_from`, heading for cell `a_to`, holding a real path, with its query
## count reset to 0. A first query can come back empty while its class's mesh is still merging
## (readiness probes only the base mesh), and an empty path re-plans on every read.
##
## With `a_is_line_tested` the unit is given a Map, so it plans the straight line when it is clear.
func _unit(a_from: Vector2i, a_to: Vector2i, a_is_line_tested: bool = false) -> CountingMovement:
	var parent := Node3D.new()
	add_child_autofree(parent)
	parent.global_position = _cell_world(a_from.x, a_from.y)
	var agent := AvoidanceAgent3D.new()
	agent.name = "NavigationAgent"
	parent.add_child(agent)
	var movement := CountingMovement.new()
	movement.nav_agent_path = NodePath("../NavigationAgent")
	parent.add_child(movement)
	var map: Map = null
	if a_is_line_tested:
		var fixture_map := FixtureMap.new()
		autofree(fixture_map)
		fixture_map.half = (W - 1) * 0.5
		fixture_map.terrain_grid = _grid
		map = fixture_map
	movement.configure_for_map(map, _nav, UNIT_RADIUS)
	movement.target_position = _cell_world(a_to.x, a_to.y)
	for _i: int in MAX_LANDING_FRAMES:
		movement.is_navigation_finished()
		if movement.current_path().size() >= 2:
			break
		await get_tree().physics_frame
	movement.queries = 0
	return movement


## A wall of building cells in column `a_x`, rows `a_z0`..`a_z1` inclusive.
func _wall(a_x: int, a_z0: int, a_z1: int) -> Array:
	var cells: Array = []
	for z: int in range(a_z0, a_z1 + 1):
		cells.append(Vector2i(a_x, z))
	_grid.place_building(cells, RefCounted.new())
	return cells


## Waits for the newest change to land, reading every unit's path each tick as the game does.
func _await_landing(a_units: Array) -> NavManager.NavChange:
	for _i: int in MAX_LANDING_FRAMES:
		await get_tree().physics_frame
		for unit: CountingMovement in a_units:
			unit.is_navigation_finished()
		if not _nav._changes.is_empty() and _nav._changes.back().is_landed:
			return _nav._changes.back()
	return null


#region The crossing test
func test_a_segment_through_the_area_touches_it() -> void:
	var area := Rect2(Vector2(0, 0), Vector2(2, 2))
	assert_true(NavManager.NavChange.segment_touches_rect(Vector2(-1, 1), Vector2(3, 1), area))
	assert_true(
		NavManager.NavChange.segment_touches_rect(Vector2(1, 1), Vector2(1, 1), area),
		"a segment inside the area"
	)
	assert_false(NavManager.NavChange.segment_touches_rect(Vector2(-1, 3), Vector2(3, 3), area))
	assert_false(
		NavManager.NavChange.segment_touches_rect(Vector2(-3, 1), Vector2(-1, 5), area),
		"passing beside the corner"
	)


func test_the_leg_from_where_the_unit_stands_counts() -> void:
	var change := NavManager.NavChange.new(1, Rect2(Vector2(0, -1), Vector2(1, 2)))
	var path := PackedVector3Array([Vector3(-5, 0, 0), Vector3(5, 0, 0), Vector3(5, 0, 5)])
	assert_true(
		change.crosses(Vector3(-5, 0, 0), path, 1),
		"standing before the area, heading for a waypoint past it"
	)


func test_legs_already_walked_do_not_count() -> void:
	var change := NavManager.NavChange.new(1, Rect2(Vector2(0, -1), Vector2(1, 2)))
	var path := PackedVector3Array([Vector3(-5, 0, 0), Vector3(5, 0, 0), Vector3(5, 0, 5)])
	assert_false(change.crosses(Vector3(5, 0, 1), path, 2), "the area is behind the unit")


#endregion


#region Landing
func test_a_change_lands_only_once_path_queries_see_it() -> void:
	await _make_nav()
	var center: int = (W - 1) / 2
	var from: Vector3 = _cell_world(center - 6, center)
	var to: Vector3 = _cell_world(center + 6, center)
	var nav_map: RID = _nav.navigation_region.get_navigation_map()
	var before: PackedVector3Array = NavigationServer3D.map_get_path(nav_map, from, to, true, 1)
	_wall(center, center - 6, center + 6)
	assert_eq(_nav.landed_serial(), 0, "recorded, not landed, before the rebuild is synced")
	var change: NavManager.NavChange = await _await_landing([])
	assert_not_null(change, "the change lands")
	var after: PackedVector3Array = NavigationServer3D.map_get_path(nav_map, from, to, true, 1)
	assert_gt(
		_length(after),
		_length(before) + 1.0,
		"by the time it has landed, a path across it goes around the wall"
	)
	assert_eq(_nav.landed_serial(), change.serial)


## The project's map is synchronous, so the regions and the map it publishes step together; an
## ASYNC map publishes a later iteration, and a change must not count as landed before it.
func test_on_an_async_map_a_change_still_lands_only_once_path_queries_see_it() -> void:
	await _make_nav()
	var nav_map: RID = _nav.navigation_region.get_navigation_map()
	NavigationServer3D.map_set_use_async_iterations(nav_map, true)
	var center: int = (W - 1) / 2
	var from: Vector3 = _cell_world(center - 6, center)
	var to: Vector3 = _cell_world(center + 6, center)
	var before: PackedVector3Array = NavigationServer3D.map_get_path(nav_map, from, to, true, 1)
	_wall(center, center - 6, center + 6)
	var change: NavManager.NavChange = await _await_landing([])
	var after: PackedVector3Array = NavigationServer3D.map_get_path(nav_map, from, to, true, 1)
	NavigationServer3D.map_set_use_async_iterations(nav_map, false)
	assert_not_null(change, "the change lands")
	assert_gt(
		_length(after),
		_length(before) + 1.0,
		"by the time it has landed, a path across it goes around the wall"
	)


func test_changes_are_handed_out_in_order_and_stop_at_one_not_yet_landed() -> void:
	var nav := NavManager.new()
	autofree(nav)
	for serial: int in [1, 2, 3]:
		nav._changes.append(NavManager.NavChange.new(serial, Rect2()))
	nav._next_change_serial = 4
	nav._changes[0].is_landed = true
	nav._changes[2].is_landed = true
	assert_eq(
		nav.landed_changes_since(0).map(func(c: NavManager.NavChange) -> int: return c.serial),
		[1],
		"change 3 waits behind change 2"
	)
	assert_eq(nav.landed_serial(), 1)
	assert_false(nav.has_forgotten(0))
	nav._changes.pop_front()
	assert_true(nav.has_forgotten(0), "change 1 is gone: a unit that last saw 0 cannot tell")
	assert_false(nav.has_forgotten(1))


func _length(a_path: PackedVector3Array) -> float:
	var total: float = 0.0
	for i: int in range(1, a_path.size()):
		total += a_path[i].distance_to(a_path[i - 1])
	return total


#endregion


#region Re-planning
func test_only_a_unit_whose_path_the_change_crosses_re_plans() -> void:
	await _make_nav()
	var center: int = (W - 1) / 2
	var crossing: CountingMovement = await _unit(
		Vector2i(center - 10, center), Vector2i(center + 10, center)
	)
	var elsewhere: CountingMovement = await _unit(Vector2i(2, 2), Vector2i(10, 2))
	assert_gt(elsewhere.current_path().size(), 1, "guards the fixture: both hold a path")
	_wall(center, center - 4, center + 4)
	var change: NavManager.NavChange = await _await_landing([crossing, elsewhere])
	assert_not_null(change)
	crossing.is_navigation_finished()
	elsewhere.is_navigation_finished()
	assert_eq(crossing.queries, 1, "the wall is on its path: it re-plans once")
	assert_eq(elsewhere.queries, 0, "the wall is nowhere near it: it keeps its path")


func test_nothing_re_plans_before_the_change_has_landed() -> void:
	await _make_nav()
	var center: int = (W - 1) / 2
	var crossing: CountingMovement = await _unit(
		Vector2i(center - 10, center), Vector2i(center + 10, center)
	)
	_wall(center, center - 4, center + 4)
	var queries_while_waiting: int = -1
	for _i: int in MAX_LANDING_FRAMES:
		await get_tree().physics_frame
		crossing.is_navigation_finished()
		if _nav._changes.back().is_landed:
			break
		queries_while_waiting = crossing.queries
	assert_eq(queries_while_waiting, 0, "a re-plan before landing would plan on the old mesh")
	assert_eq(crossing.queries, 1, "guards the test: it does re-plan once the change lands")


func test_a_path_that_stops_short_re_plans_only_on_a_change_around_its_target() -> void:
	await _make_nav()
	var center: int = (W - 1) / 2
	# The target sits inside a closed box, so the path stops short of it. The box's east cell is
	# a separate footprint, so it can be opened on its own: a gate on the far side from the unit.
	var gate := Vector2i(center + 2, center)
	var box: Array = []
	for d: int in range(-2, 3):
		box.append_array([Vector2i(center + d, center - 2), Vector2i(center + d, center + 2)])
	for d: int in range(-1, 2):
		box.append(Vector2i(center - 2, center + d))
		if center + d != gate.y:
			box.append(Vector2i(center + 2, center + d))
	_grid.place_building(box, RefCounted.new())
	var gate_owner := RefCounted.new()
	_grid.place_building([gate], gate_owner)
	await _await_landing([])
	var boxed_out: CountingMovement = await _unit(Vector2i(4, center), Vector2i(center, center))
	assert_gt(
		VU.inXZ(boxed_out.current_path()[-1]).distance_to(VU.inXZ(_cell_world(center, center))),
		1.0,
		"guards the fixture: the path stops short of the boxed-in target"
	)
	# A change far from the target cannot open the way.
	_wall(4, 40, 44)
	assert_not_null(await _await_landing([boxed_out]))
	boxed_out.is_navigation_finished()
	assert_eq(boxed_out.queries, 0, "a change nowhere near the target leaves the path alone")
	# Opening the gate can.
	_grid.remove_building(gate_owner)
	assert_not_null(await _await_landing([boxed_out]))
	boxed_out.is_navigation_finished()
	assert_eq(boxed_out.queries, 1, "a change around the target re-plans, even on its far side")
	assert_lt(
		VU.inXZ(boxed_out.current_path()[-1]).distance_to(VU.inXZ(_cell_world(center, center))),
		0.5,
		"and the new path reaches the target through the gate"
	)


#endregion


#region Straight-line planning
func test_a_clear_line_is_planned_as_itself() -> void:
	await _make_nav()
	var unit: CountingMovement = await _unit(Vector2i(4, 4), Vector2i(30, 20), true)
	assert_eq(unit.current_path().size(), 2, "the unit and its target, nothing between")
	assert_eq(unit.current_path()[1], _cell_world(30, 20))


func test_a_chaser_with_its_quarry_in_sight_never_queries() -> void:
	await _make_nav()
	var chaser: CountingMovement = await _unit(Vector2i(4, 24), Vector2i(20, 24), true)
	for tick: int in 30:
		# The quarry moves every tick, as a pursued enemy does.
		chaser.target_position = _cell_world(20, 24) + Vector3(0.0, 0.0, tick * 0.1)
		chaser.is_navigation_finished()
		await get_tree().physics_frame
	assert_eq(chaser.queries, 0)
	assert_eq(chaser.current_path()[-1], chaser.target_position, "it steers at where it is now")


func test_a_blocked_line_still_queries_the_navmesh() -> void:
	await _make_nav()
	var center: int = (W - 1) / 2
	_wall(center, center - 6, center + 6)
	await _await_landing([])
	var unit: CountingMovement = await _unit(
		Vector2i(center - 8, center), Vector2i(center + 8, center), true
	)
	unit.target_position = _cell_world(center + 8, center + 1)
	unit.is_navigation_finished()
	assert_eq(unit.queries, 1)
	assert_gt(unit.current_path().size(), 2, "the path goes around the wall")


func test_a_change_across_a_straight_path_re_plans_around_it() -> void:
	await _make_nav()
	var center: int = (W - 1) / 2
	var unit: CountingMovement = await _unit(
		Vector2i(center - 8, center), Vector2i(center + 8, center), true
	)
	assert_eq(unit.current_path().size(), 2, "guards the fixture: a straight path")
	_wall(center, center - 6, center + 6)
	assert_not_null(await _await_landing([unit]))
	unit.is_navigation_finished()
	assert_eq(unit.queries, 1)
	assert_gt(unit.current_path().size(), 2)
#endregion
