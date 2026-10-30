extends GutTest

## THE BOT'S REACHABILITY QUERY CARRIES A UNIT'S POLYGON BUDGET.
##
## Godot's A* explores at most `path_search_max_polygons` (4096 by default) and then answers
## with the PARTIAL path to the nearest polygon it reached, not with an error. On this game's
## one-quad-per-cell mesh a walk across a skirmish map that has to go round anything exhausts
## that budget, so Bot.is_reachable — the filter every attack objective passes — read every
## structure in the enemy's main base as unreachable, and the army massed at home for a match
## (bot-engagement-fixes.md §The objective nobody could reach). Movement already raised its
## agents' budget (Movement.PATH_SEARCH_MAX_POLYGONS); Bot.walk_path asks with the same one.
##
## The fixture is a flat map with a wall across it, open at one end, so the straight line is
## blocked and the search has to sweep most of one half before it finds the way round.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_BotReachability.gd

## Cells per side: enough that the sweep behind the wall passes Godot's default budget.
const CELLS: int = 100
const W: int = CELLS + 1  # corners
const MAX_READY_FRAMES: int = 300
const WALL_COLUMN: int = CELLS / 2
## The wall leaves this many open cells at the far (high-z) end.
const GAP_CELLS: int = 3
const ROW: int = 4

var _grid: TerrainGrid
var _nav: NavManager


func before_each() -> void:
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
	var wall: Array = []
	for z: int in range(0, CELLS - GAP_CELLS):
		wall.append(Vector2i(WALL_COLUMN, z))
	_grid.place_building(wall, autofree(Node.new()))
	assert_true(
		await _nav.await_excluded([_cell_world(WALL_COLUMN, ROW)] as Array[Vector3]),
		"the wall's cells leave the navmesh"
	)


func _cell_world(a_x: int, a_z: int) -> Vector3:
	var half: float = (W - 1) * 0.5
	return Vector3(a_x + 0.5 - half, 0.0, a_z + 0.5 - half)


func _end_gap(a_path: PackedVector3Array, a_to: Vector3) -> float:
	if a_path.is_empty():
		return INF
	return VU.in_xz(a_path[a_path.size() - 1]).distance_to(VU.in_xz(a_to))


func test_the_default_budget_answers_a_long_detour_with_a_partial_path() -> void:
	# The trap this file guards against, pinned so the fixture is known to exercise it: if
	# Godot's default ever grows past the sweep this map forces, the test below proves nothing.
	var nav_map: RID = _nav.navigation_region.get_navigation_map()
	var from: Vector3 = _cell_world(3, ROW)
	var to: Vector3 = _cell_world(CELLS - 4, ROW)
	var partial: PackedVector3Array = NavigationServer3D.map_get_path(nav_map, from, to, true)
	assert_gt(_end_gap(partial, to), 1.0, "the default query stops short of the far side")


func test_walk_path_reaches_the_far_side_of_the_wall() -> void:
	var nav_map: RID = _nav.navigation_region.get_navigation_map()
	var from: Vector3 = _cell_world(3, ROW)
	var to: Vector3 = _cell_world(CELLS - 4, ROW)
	var path: PackedVector3Array = Bot.walk_path(nav_map, from, to)
	assert_lt(_end_gap(path, to), 1.0, "the budgeted query reaches the target")
	assert_gt(path.size(), 2, "and it is the detour round the wall's open end, not a straight line")


func test_walk_path_still_stops_short_of_ground_that_is_cut_off() -> void:
	# Close the gap: now nothing on the far side can be reached, and the budget must not be
	# what says so — the partial path ends at the wall, however many polygons are allowed.
	var plug: Array = []
	for z: int in range(CELLS - GAP_CELLS, CELLS):
		plug.append(Vector2i(WALL_COLUMN, z))
	_grid.place_building(plug, autofree(Node.new()))
	assert_true(
		await _nav.await_excluded([_cell_world(WALL_COLUMN, CELLS - 1)] as Array[Vector3]),
		"the plug's cells leave the navmesh"
	)
	var nav_map: RID = _nav.navigation_region.get_navigation_map()
	var from: Vector3 = _cell_world(3, ROW)
	var to: Vector3 = _cell_world(CELLS - 4, ROW)
	var path: PackedVector3Array = Bot.walk_path(nav_map, from, to)
	assert_gt(_end_gap(path, to), 10.0, "cut off: the path ends on the near side of the wall")
