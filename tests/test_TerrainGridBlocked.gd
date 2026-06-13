extends GutTest

## Tests for TerrainGrid's blocked-mask hook — impassability beyond terrain height.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_TerrainGridBlocked.gd

const W: int = 6  # 6x6 corners -> 5x5 = 25 cells, all flat/passable


func _make_grid() -> TerrainGrid:
	var shape := HeightMapShape3D.new()
	shape.map_width = W
	shape.map_depth = W
	var data := PackedFloat32Array()
	data.resize(W * W)  # all zeros -> every cell flat and passable
	shape.map_data = data

	var body := StaticBody3D.new()
	add_child_autofree(body)

	var grid := TerrainGrid.new()
	grid.height_map = shape
	grid.terrain_body = body
	add_child_autofree(grid)  # _ready computes steep cells (none here)
	return grid


func test_unblocked_grid_is_fully_passable():
	var grid := _make_grid()
	assert_true(grid.is_passable(Vector2i(2, 2)))
	assert_false(grid.is_blocked(Vector2i(2, 2)))
	assert_eq(grid.get_all_passable_cells().size(), 25)


func test_set_blocked_makes_cell_impassable():
	var grid := _make_grid()
	grid.set_blocked(Vector2i(2, 2), true)
	assert_true(grid.is_blocked(Vector2i(2, 2)))
	assert_false(grid.is_passable(Vector2i(2, 2)), "blocked cell is not passable")
	assert_true(grid.is_passable(Vector2i(0, 0)), "other cells unaffected")
	assert_eq(grid.get_all_passable_cells().size(), 24, "blocked cell drops out of passable set")


func test_blocked_mask_bulk_set_and_clear():
	var grid := _make_grid()
	var gw: int = grid.grid_width()
	var gh: int = grid.grid_depth()
	var mask := PackedByteArray()
	mask.resize(gw * gh)
	mask[2 * gw + 1] = 1  # block (1,2)
	mask[3 * gw + 4] = 1  # block (4,3)
	grid.set_blocked_mask(mask)

	assert_true(grid.is_blocked(Vector2i(1, 2)))
	assert_true(grid.is_blocked(Vector2i(4, 3)))
	assert_eq(grid.get_all_passable_cells().size(), 23)

	grid.clear_blocked_mask()
	assert_false(grid.is_blocked(Vector2i(1, 2)))
	assert_eq(grid.get_all_passable_cells().size(), 25, "clearing restores all cells")


func test_set_blocked_mask_emits_cells_changed():
	var grid := _make_grid()
	watch_signals(grid)
	var gw: int = grid.grid_width()
	var mask := PackedByteArray()
	mask.resize(gw * grid.grid_depth())
	mask[2 * gw + 2] = 1
	grid.set_blocked_mask(mask)
	# NavManager relies on this to rebuild the navmesh excluding blocked cells.
	assert_signal_emitted(grid, "cells_changed")


func test_out_of_bounds_is_never_blocked():
	var grid := _make_grid()
	grid.set_blocked(Vector2i(2, 2), true)
	assert_false(grid.is_blocked(Vector2i(-1, 0)))
	assert_false(grid.is_blocked(Vector2i(100, 100)))
