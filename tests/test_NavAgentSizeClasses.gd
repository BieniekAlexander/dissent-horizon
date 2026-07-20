extends GutTest

## Tests for the per-size-class space-erosion used to bake one navmesh per
## NavAgentClass.Size (see nav-agent-size-classes.md). Covers:
##   - NavAgentClass erosion parameters derived from the radii
##   - TerrainGrid clearance / distance fields
##   - TerrainGrid.get_navigable_cells hallway-admission semantics per class
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_NavAgentSizeClasses.gd

const CS: float = Map.CELL_SIZE


# --- NavAgentClass parameters ----------------------------------------------

func test_radii_are_half_corridor_width_minus_margin():
	# radius = tier * cs / 2 - CLEARANCE_MARGIN. At cs=1, margin=0.05.
	var m: float = NavAgentClass.CLEARANCE_MARGIN
	assert_almost_eq(NavAgentClass.radius(NavAgentClass.Size.SMALL,  CS), 0.5 - m, 1e-5)
	assert_almost_eq(NavAgentClass.radius(NavAgentClass.Size.MEDIUM, CS), 1.0 - m, 1e-5)
	assert_almost_eq(NavAgentClass.radius(NavAgentClass.Size.LARGE,  CS), 1.5 - m, 1e-5)


func test_required_clearance_is_min_corridor_width():
	# The tier itself (enum value): SMALL=1-cell, MEDIUM=2-cell, LARGE=3-cell.
	assert_eq(NavAgentClass.required_clearance(NavAgentClass.Size.SMALL,  CS), 1)
	assert_eq(NavAgentClass.required_clearance(NavAgentClass.Size.MEDIUM, CS), 2)
	assert_eq(NavAgentClass.required_clearance(NavAgentClass.Size.LARGE,  CS), 3)


func test_class_for_radius_picks_smallest_large_enough():
	# Interior of each band (kept off the exact 0.45/0.95 boundaries, which are
	# float-fragile) maps to the expected tier.
	assert_eq(NavAgentClass.class_for_radius(0.2, CS), NavAgentClass.Size.SMALL)
	assert_eq(NavAgentClass.class_for_radius(0.4, CS), NavAgentClass.Size.SMALL)
	assert_eq(NavAgentClass.class_for_radius(0.5, CS), NavAgentClass.Size.MEDIUM)
	assert_eq(NavAgentClass.class_for_radius(1.0, CS), NavAgentClass.Size.LARGE)
	# Regression: a body just over the SMALL ceiling (0.45) needs 2 cells, not 3 —
	# the carronade case. 0.70 and 0.75 must BOTH be MEDIUM (no tier cliff at 0.70).
	assert_eq(NavAgentClass.class_for_radius(0.70, CS), NavAgentClass.Size.MEDIUM)
	assert_eq(NavAgentClass.class_for_radius(0.75, CS), NavAgentClass.Size.MEDIUM)
	# Tiny / zero / negative (missing shape) falls to the smallest class.
	assert_eq(NavAgentClass.class_for_radius(0.05, CS), NavAgentClass.Size.SMALL)
	assert_eq(NavAgentClass.class_for_radius(-1.0, CS), NavAgentClass.Size.SMALL)
	# Bigger than every class radius clamps to LARGE.
	assert_eq(NavAgentClass.class_for_radius(5.0, CS), NavAgentClass.Size.LARGE)


func test_erosion_rings_and_inset():
	# rings + inset reconstruct the class radius (rings whole cells + a sub-cell
	# remainder). At cs=1 only LARGE (r=1.45) strips a whole ring.
	assert_eq(NavAgentClass.erosion_rings(NavAgentClass.Size.SMALL,  CS), 0)
	assert_eq(NavAgentClass.erosion_rings(NavAgentClass.Size.MEDIUM, CS), 0)
	assert_eq(NavAgentClass.erosion_rings(NavAgentClass.Size.LARGE,  CS), 1)

	var m: float = NavAgentClass.CLEARANCE_MARGIN
	assert_almost_eq(NavAgentClass.inset(NavAgentClass.Size.SMALL,  CS), 0.5 - m, 1e-5)
	assert_almost_eq(NavAgentClass.inset(NavAgentClass.Size.MEDIUM, CS), 1.0 - m, 1e-5)
	assert_almost_eq(NavAgentClass.inset(NavAgentClass.Size.LARGE,  CS), 0.5 - m, 1e-5)

	# The inset is always strictly sub-cell, so it can't overshoot an interior vertex.
	for size: int in NavAgentClass.Size.values():
		assert_lt(NavAgentClass.inset(size, CS), CS,
			"inset for size %d must be < CELL_SIZE" % size)


# --- TerrainGrid clearance / distance fields -------------------------------

func _make_grid(w: int) -> TerrainGrid:
	var shape := HeightMapShape3D.new()
	shape.map_width = w
	shape.map_depth = w
	var data := PackedFloat32Array()
	data.resize(w * w)  # all zeros -> every cell flat and passable
	shape.map_data = data

	var body := StaticBody3D.new()
	add_child_autofree(body)

	var grid := TerrainGrid.new()
	grid.height_map = shape
	grid.terrain_body = body
	add_child_autofree(grid)
	return grid


## Block every cell outside a centred, full-width horizontal band `width` cells tall,
## leaving a corridor of that width. Returns the grid; the band is centred on the
## grid's middle row so cell (gw/2, gh/2) is always inside it.
func _make_corridor(corner_w: int, width: int) -> TerrainGrid:
	var grid := _make_grid(corner_w)
	var gw: int = grid.grid_width()
	var gh: int = grid.grid_depth()
	var z0: int = (gh - width) / 2
	var mask := PackedByteArray()
	mask.resize(gw * gh)
	for z: int in gh:
		for x: int in gw:
			if z < z0 or z >= z0 + width:
				mask[z * gw + x] = 1
	grid.set_blocked_mask(mask)
	return grid


func test_clearance_open_field():
	# In a fully-open grid, the corner cell anchors the largest square (the whole grid).
	var grid := _make_grid(6)  # 5x5 cells
	assert_eq(grid.clearance_at(Vector2i(0, 0)), 5)
	assert_eq(grid.clearance_at(Vector2i(4, 4)), 1, "bottom-right corner fits only 1x1")


func test_clearance_zero_on_blocked():
	var grid := _make_grid(6)
	grid.set_blocked(Vector2i(2, 2), true)
	assert_eq(grid.clearance_at(Vector2i(2, 2)), 0)


func test_distance_to_obstacle():
	var grid := _make_grid(7)  # 6x6 cells
	grid.set_blocked(Vector2i(3, 3), true)
	assert_eq(grid.distance_to_obstacle(Vector2i(3, 3)), 0, "the obstacle itself")
	assert_eq(grid.distance_to_obstacle(Vector2i(2, 3)), 1, "cell touching the obstacle")
	assert_eq(grid.distance_to_obstacle(Vector2i(1, 3)), 2)


# --- Per-class hallway admission -------------------------------------------

## Whether the centre cell of a width-`width` corridor is in the navigable set for
## a given size class.
func _admits(width: int, size: int) -> bool:
	var grid := _make_corridor(14, width)  # 13x13 cells; band centred on row 6
	var mid := Vector2i(grid.grid_width() / 2, grid.grid_depth() / 2)
	var rings: int = NavAgentClass.erosion_rings(size, CS)
	var admit_k: int = NavAgentClass.required_clearance(size, CS)
	return grid.get_navigable_cells(rings, admit_k).has(mid)


func test_one_cell_hallway_admits_small_only():
	assert_true(_admits(1, NavAgentClass.Size.SMALL),  "SMALL fits a 1-cell hallway")
	assert_false(_admits(1, NavAgentClass.Size.MEDIUM),"MEDIUM needs a 2-cell hallway")
	assert_false(_admits(1, NavAgentClass.Size.LARGE), "LARGE needs a 3-cell hallway")


func test_two_cell_hallway_admits_up_to_medium():
	assert_true(_admits(2, NavAgentClass.Size.SMALL))
	assert_true(_admits(2, NavAgentClass.Size.MEDIUM), "MEDIUM fits a 2-cell hallway")
	assert_false(_admits(2, NavAgentClass.Size.LARGE), "LARGE still needs 3 cells")


func test_three_cell_hallway_admits_all():
	assert_true(_admits(3, NavAgentClass.Size.SMALL))
	assert_true(_admits(3, NavAgentClass.Size.MEDIUM))
	assert_true(_admits(3, NavAgentClass.Size.LARGE), "LARGE fits a 3-cell hallway")


## End-to-end regression for the carronade tier cliff: a 0.75-radius body classifies
## as MEDIUM and can traverse a 2-cell corridor but NOT a 1-cell one — and 0.70 (which
## used to flip a whole tier) behaves identically.
func test_carronade_radius_traverses_two_cell_not_one():
	for r: float in [0.70, 0.75]:
		var size: int = NavAgentClass.class_for_radius(r, CS)
		assert_eq(size, NavAgentClass.Size.MEDIUM, "radius %s -> MEDIUM" % r)
		assert_false(_admits(1, size), "radius %s excluded from a 1-cell corridor" % r)
		assert_true(_admits(2, size),  "radius %s admitted to a 2-cell corridor" % r)


func test_navigable_subset_of_passable():
	# Every navigable cell (any class) must be passable.
	var grid := _make_corridor(14, 3)
	for size: int in NavAgentClass.Size.values():
		var rings: int = NavAgentClass.erosion_rings(size, CS)
		var admit_k: int = NavAgentClass.required_clearance(size, CS)
		for cell: Vector2i in grid.get_navigable_cells(rings, admit_k):
			assert_true(grid.is_passable(cell),
				"size %d navigable cell %s must be passable" % [size, cell])
