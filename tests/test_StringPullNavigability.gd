extends GutTest

## Tests for TerrainGrid.is_navigable_for — the per-cell rule Movement's string-pull asks of
## every cell under a candidate straight line.
##
## This is the safety-critical half of path straightening: the string-pull steers at the
## furthest waypoint it believes is directly reachable, so if this rule is more permissive than
## the one the navmesh was baked with, units walk through ground their own navmesh excluded.
## The two therefore must agree — get_navigable_cells goes through the bulk navigable_mask —
## and the first test pins that they cannot drift.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_StringPullNavigability.gd

const W: int = 12  # 12x12 corners -> 11x11 cells


func _make_grid() -> TerrainGrid:
	var shape := HeightMapShape3D.new()
	shape.map_width = W
	shape.map_depth = W
	var data := PackedFloat32Array()
	data.resize(W * W)          # flat -> every cell passable
	shape.map_data = data

	var body := StaticBody3D.new()
	add_child_autofree(body)

	var grid := TerrainGrid.new()
	grid.height_map = shape
	grid.terrain_body = body
	add_child_autofree(grid)
	return grid


## The property everything else rests on: the single-cell rule and the whole-grid bake must
## select exactly the same set, for every erosion setting.
func test_agrees_with_get_navigable_cells():
	var grid := _make_grid()
	grid.place_building([Vector2i(5, 5), Vector2i(5, 6)], self)
	for rings: int in [0, 1, 2]:
		for admit_k: int in [1, 2, 3]:
			var baked: Dictionary = grid.get_navigable_cells(rings, admit_k)
			var mismatches: int = 0
			for z: int in grid.grid_depth():
				for x: int in grid.grid_width():
					var cell := Vector2i(x, z)
					if grid.is_navigable_for(cell, rings, admit_k) != baked.has(cell):
						mismatches += 1
			assert_eq(mismatches, 0,
				"rings=%d admit_k=%d must select the same cells" % [rings, admit_k])


func test_an_impassable_cell_is_never_navigable():
	var grid := _make_grid()
	grid.place_building([Vector2i(4, 4)], self)
	assert_false(grid.is_navigable_for(Vector2i(4, 4), 0, 1),
		"a building cell is refused even with no erosion")


func test_out_of_bounds_is_not_navigable():
	var grid := _make_grid()
	# A string-pull segment leaving the map must be refused, or a unit would be steered off it.
	assert_false(grid.is_navigable_for(Vector2i(-1, 3), 0, 1))
	assert_false(grid.is_navigable_for(Vector2i(3, -1), 0, 1))
	assert_false(grid.is_navigable_for(Vector2i(grid.grid_width(), 3), 0, 1))
	assert_false(grid.is_navigable_for(Vector2i(3, grid.grid_depth()), 0, 1))


func test_open_ground_is_navigable_for_the_smallest_class():
	var grid := _make_grid()
	assert_true(grid.is_navigable_for(Vector2i(5, 5), 0, 1), "flat empty ground")


## Ring erosion is what keeps a larger unit off the cells hugging an obstacle. The string-pull
## must honour it, or a large unit would be steered along a line only a small one fits down.
func test_ring_erosion_excludes_cells_beside_an_obstacle():
	var grid := _make_grid()
	grid.place_building([Vector2i(5, 5)], self)
	var beside := Vector2i(6, 5)
	assert_true(grid.is_navigable_for(beside, 0, 1),
		"with no erosion, the neighbouring cell is navigable")
	assert_false(grid.is_navigable_for(beside, 1, 1),
		"one ring of erosion strips the cell touching the obstacle")


## A corridor one cell wide admits a small unit and refuses a large one — the case where a
## permissive string-pull would visibly walk a big unit through a gap it cannot fit.
func test_a_narrow_gap_admits_small_but_not_large():
	var grid := _make_grid()
	# Wall across z = 5 with a single-cell gap at x = 5.
	var wall: Array = []
	for x: int in grid.grid_width():
		if x != 5:
			wall.append(Vector2i(x, 5))
	grid.place_building(wall, self)
	assert_true(grid.is_navigable_for(Vector2i(5, 5), 0, 1), "the gap is open to a 1-cell unit")
	assert_false(grid.is_navigable_for(Vector2i(5, 5), 0, 2),
		"a unit needing a 2x2 block cannot use a one-cell gap")


## The navmesh builds each chunk from navigable_mask over a SUB-rectangle, so the bulk form must
## agree with the single-cell rule on every rectangle — including ones clipped against the grid
## edge, where the admission window is cut short.
func test_navigable_mask_agrees_on_sub_rectangles():
	var grid := _make_grid()
	grid.place_building([Vector2i(5, 5), Vector2i(5, 6), Vector2i(0, 3)], self)
	var rects: Array[Rect2i] = [
		Rect2i(0, 0, 4, 4), Rect2i(3, 4, 5, 3), Rect2i(7, 7, 4, 4), grid.get_bounds_rect(),
	]
	for rect: Rect2i in rects:
		for rings: int in [0, 1, 2]:
			for admit_k: int in [1, 2, 3]:
				var mask: PackedByteArray = grid.navigable_mask(rect, rings, admit_k)
				var mismatches: int = 0
				var i: int = 0
				for z: int in range(rect.position.y, rect.end.y):
					for x: int in range(rect.position.x, rect.end.x):
						if grid.is_navigable_for(Vector2i(x, z), rings, admit_k) != (mask[i] != 0):
							mismatches += 1
						i += 1
				assert_eq(mismatches, 0, "%s rings=%d admit_k=%d" % [rect, rings, admit_k])


#region The segment walk
## Whether segment `a`→`b` touches cell `c`'s closed square, by clipping the segment against it
## (Liang–Barsky): the exact geometric reference the walk is checked against.
func _segment_touches_cell(a: Vector2, b: Vector2, c: Vector2i) -> bool:
	var d: Vector2 = b - a
	var t0: float = 0.0
	var t1: float = 1.0
	for axis: int in 2:
		var lo: float = float(c[axis])
		var hi: float = lo + 1.0
		if is_zero_approx(d[axis]):
			if a[axis] < lo or a[axis] > hi:
				return false
			continue
		var ta: float = (lo - a[axis]) / d[axis]
		var tb: float = (hi - a[axis]) / d[axis]
		t0 = maxf(t0, minf(ta, tb))
		t1 = minf(t1, maxf(ta, tb))
		if t0 > t1:
			return false
	return true


## Every cell the segment touches must be navigable — cells off the grid included, which are not.
func _reference_segment(grid: TerrainGrid, a: Vector2, b: Vector2, rings: int, admit_k: int) -> bool:
	for z: int in range(-1, grid.grid_depth() + 1):
		for x: int in range(-1, grid.grid_width() + 1):
			var cell := Vector2i(x, z)
			if _segment_touches_cell(a, b, cell) and not grid.is_navigable_for(cell, rings, admit_k):
				return false
	return true


## The walk visits exactly the cells a segment crosses: random segments, some leaving the grid,
## over scattered obstacles and every erosion setting, agree with the geometric reference.
func test_segment_walk_agrees_with_the_cells_the_segment_touches():
	var grid := _make_grid()
	grid.place_building([Vector2i(5, 5), Vector2i(2, 7), Vector2i(8, 3), Vector2i(8, 4)], self)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260926
	var mismatches: int = 0
	var refusals: int = 0
	for trial: int in 400:
		var a := Vector2(rng.randf_range(-0.5, W - 0.5), rng.randf_range(-0.5, W - 0.5))
		var b := Vector2(rng.randf_range(-0.5, W - 0.5), rng.randf_range(-0.5, W - 0.5))
		for rings: int in [0, 1]:
			for admit_k: int in [1, 2]:
				var expected: bool = _reference_segment(grid, a, b, rings, admit_k)
				if not expected:
					refusals += 1
				if grid.is_segment_navigable_for(a, b, rings, admit_k) != expected:
					mismatches += 1
	assert_gt(refusals, 100, "guards the fixture: plenty of segments are blocked")
	assert_eq(mismatches, 0)


## A diagonal passing exactly through a corner touches all four cells around it, so two blocked
## cells meeting at that corner close it, even though the line never enters their interiors.
func test_a_diagonal_cannot_slip_between_two_blocked_cells_meeting_at_a_corner():
	var grid := _make_grid()
	grid.place_building([Vector2i(5, 4), Vector2i(4, 5)], self)
	assert_false(grid.is_segment_navigable_for(Vector2(4.5, 4.5), Vector2(5.5, 5.5), 0, 1))
	assert_true(grid.is_segment_navigable_for(Vector2(6.5, 6.5), Vector2(7.5, 7.5), 0, 1),
		"guards the fixture: the same kind of diagonal elsewhere is open")


func test_a_segment_within_one_cell_asks_about_that_cell() -> void:
	var grid := _make_grid()
	grid.place_building([Vector2i(3, 3)], self)
	assert_false(grid.is_segment_navigable_for(Vector2(3.2, 3.2), Vector2(3.8, 3.3), 0, 1))
	assert_true(grid.is_segment_navigable_for(Vector2(6.2, 6.2), Vector2(6.2, 6.2), 0, 1))
#endregion
