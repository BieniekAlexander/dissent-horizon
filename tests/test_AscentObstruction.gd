extends GutTest

## The march behind an ascending aircraft's speed cap: how far along a heading the first cell
## holding a building (or off the grid) begins. Aerial.distance_to_obstruction.

const _CELLS: int = 10
const _FAR: float = 100.0

var _grid: TerrainGrid


func before_each() -> void:
	var shape := HeightMapShape3D.new()
	shape.map_width = _CELLS + 1
	shape.map_depth = _CELLS + 1
	_grid = TerrainGrid.new()
	_grid.height_map = shape
	_grid.terrain_body = autofree(StaticBody3D.new())
	add_child_autofree(_grid)


func test_a_building_ahead_is_found_at_its_near_edge() -> void:
	_grid.place_building([Vector2i(5, 2)], self)
	assert_almost_eq(
		Aerial.distance_to_obstruction(_grid, Vector2(2.5, 2.5), Vector2.RIGHT, _FAR), 2.5, 1e-5
	)


func test_a_building_beyond_reach_is_not() -> void:
	_grid.place_building([Vector2i(5, 2)], self)
	assert_eq(Aerial.distance_to_obstruction(_grid, Vector2(2.5, 2.5), Vector2.RIGHT, 2.0), INF)


func test_a_building_off_the_heading_is_not() -> void:
	_grid.place_building([Vector2i(5, 4)], self)
	assert_eq(Aerial.distance_to_obstruction(_grid, Vector2(2.5, 2.5), Vector2.RIGHT, 5.0), INF)


func test_the_grid_edge_obstructs() -> void:
	assert_almost_eq(
		Aerial.distance_to_obstruction(_grid, Vector2(2.5, 2.5), Vector2.LEFT, _FAR), 2.5, 1e-5
	)


func test_a_diagonal_heading_crosses_both_axes() -> void:
	_grid.place_building([Vector2i(4, 4)], self)
	var dir: Vector2 = Vector2.ONE.normalized()
	# From (2.5, 2.5) the diagonal enters (3, 3) and then (4, 4) at the corner (4, 4).
	var distance: float = Aerial.distance_to_obstruction(_grid, Vector2(2.5, 2.5), dir, _FAR)
	assert_true(distance < INF, "found")
	assert_almost_eq(distance, Vector2(1.5, 1.5).length(), 1e-4)
