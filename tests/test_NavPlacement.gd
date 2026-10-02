extends GutTest

## THE TWO NAVIGATION RULES A PLACEMENT HAS TO MEET, and the cost of asking.
##
## Rule 1 — a footprint may not split the walkable surface. Rule 2 — a structure units have
## to reach needs a whole side on walkable ground. Both live in the map layer
## (`NavPlacement`) rather than in the bot, because both are facts about the map: the human
## player's placement validation wants the same answers.
##
## The connectivity rule is checked against `TerrainGrid.placement_preserves_connectivity`,
## the brute-force flood fill it replaces, on every cell of a maze-ish fixture. That is the
## whole point of the local algorithm: it must agree with the definition everywhere, not
## merely on the cases someone thought to write down.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_NavPlacement.gd -gexit


## A TerrainGrid over a flat W x W corner heightmap — (W-1) x (W-1) passable cells.
func _make_grid(a_corners: int) -> TerrainGrid:
	var shape := HeightMapShape3D.new()
	shape.map_width = a_corners
	shape.map_depth = a_corners
	var data := PackedFloat32Array()
	data.resize(a_corners * a_corners)
	shape.map_data = data

	var body := StaticBody3D.new()
	add_child_autofree(body)

	var grid := TerrainGrid.new()
	grid.height_map = shape
	grid.terrain_body = body
	add_child_autofree(grid)
	return grid


## Block every cell of `a_cells`, as terrain would.
func _block(a_grid: TerrainGrid, a_cells: Array) -> void:
	for cell: Vector2i in a_cells:
		a_grid.set_blocked(cell, true)


func _rect(a_x: int, a_z: int, a_w: int, a_d: int) -> Array:
	var out: Array = []
	for i: int in a_w:
		for j: int in a_d:
			out.append(Vector2i(a_x + i, a_z + j))
	return out


# ─── REGION LABELS ──────────────────────────────────────────────────────────


func test_an_open_grid_is_one_region() -> void:
	var grid := _make_grid(9)
	assert_eq(grid.component_count(), 1)
	assert_eq(grid.component_at(Vector2i(0, 0)), grid.component_at(Vector2i(7, 7)))
	assert_eq(grid.component_size(grid.component_at(Vector2i(0, 0))), 64)


func test_a_wall_splits_the_labels_and_an_opening_rejoins_them() -> void:
	var grid := _make_grid(9)  # 8 x 8 cells
	_block(grid, _rect(4, 0, 1, 8))  # a full-height wall at x = 4
	assert_eq(grid.component_count(), 2, "the wall makes two regions")
	assert_ne(grid.component_at(Vector2i(0, 0)), grid.component_at(Vector2i(7, 7)))
	grid.set_blocked(Vector2i(4, 3), false)  # punch a door
	assert_eq(grid.component_count(), 1, "the labels are rebuilt when cells change")
	assert_eq(grid.component_at(Vector2i(0, 0)), grid.component_at(Vector2i(7, 7)))


func test_an_impassable_cell_belongs_to_no_region() -> void:
	var grid := _make_grid(9)
	grid.set_blocked(Vector2i(2, 2), true)
	assert_eq(grid.component_at(Vector2i(2, 2)), -1)
	assert_eq(grid.component_at(Vector2i(-1, 0)), -1, "and neither does off-map")


func test_the_largest_region_is_the_one_with_the_most_cells() -> void:
	var grid := _make_grid(9)
	_block(grid, _rect(2, 0, 1, 8))  # 2 cells left of it, 5 right of it
	var big: int = grid.largest_component()
	assert_eq(grid.component_at(Vector2i(7, 0)), big)
	assert_eq(grid.component_size(big), 40)


# ─── RULE 1: THE PLACEMENT MAY NOT SPLIT THE WALKABLE SURFACE ───────────────


func test_a_footprint_in_the_open_is_accepted() -> void:
	var grid := _make_grid(13)
	assert_true(NavPlacement.preserves_connectivity(grid, _rect(4, 4, 2, 2)))


func test_a_footprint_that_plugs_a_corridor_is_refused() -> void:
	var grid := _make_grid(13)  # 12 x 12
	# A wall across the map with a single two-cell gate at z = 5..6.
	_block(grid, _rect(6, 0, 1, 5))
	_block(grid, _rect(6, 7, 1, 5))
	assert_eq(grid.component_count(), 1, "the gate keeps it one region to begin with")
	assert_false(
		NavPlacement.preserves_connectivity(grid, [Vector2i(6, 5), Vector2i(6, 6)]),
		"filling the only gate walls off half the map"
	)
	assert_true(
		NavPlacement.preserves_connectivity(grid, [Vector2i(6, 5)]),
		"filling half of it still leaves a way through"
	)


func test_a_footprint_on_ground_nobody_can_walk_costs_nothing() -> void:
	var grid := _make_grid(13)
	_block(grid, _rect(6, 0, 1, 12))  # already two regions
	assert_true(
		NavPlacement.preserves_connectivity(grid, _rect(6, 4, 1, 3)),
		"blocking cells that are already impassable changes no path"
	)


func test_a_footprint_that_fills_a_dead_end_is_accepted() -> void:
	# A blind alcove, filled to its mouth. Nothing is stranded because nothing is left, so
	# the region count does not go up and the placement is legal.
	var grid := _make_grid(13)
	_block(grid, _rect(4, 0, 1, 4))
	_block(grid, _rect(6, 0, 1, 4))  # alcove is x = 5, z = 0..3
	var alcove: Array = _rect(5, 0, 1, 4)
	assert_true(NavPlacement.preserves_connectivity(grid, alcove))
	assert_true(grid.placement_preserves_connectivity(alcove), "and the flood fill agrees")


func test_a_footprint_that_seals_a_pocket_and_leaves_it_there_is_refused() -> void:
	# The other half of the same idea: sealing the mouth but leaving walkable ground behind
	# it strands that ground, which is exactly the trap the rule exists to stop.
	var grid := _make_grid(13)
	_block(grid, _rect(4, 0, 1, 4))
	_block(grid, _rect(6, 0, 1, 4))
	assert_false(
		NavPlacement.preserves_connectivity(grid, [Vector2i(5, 3)]),
		"z = 0..2 of the alcove would be walkable and unreachable"
	)


func test_it_agrees_with_the_brute_force_flood_fill_everywhere() -> void:
	# THE REAL TEST. The local algorithm has to agree with the DEFINITION on every cell of a
	# fixture with corridors, pockets and open ground — not just on the cases above.
	var grid := _make_grid(15)  # 14 x 14
	_block(grid, _rect(4, 0, 1, 5))
	_block(grid, _rect(4, 7, 1, 7))
	_block(grid, _rect(9, 2, 1, 10))
	_block(grid, _rect(5, 11, 5, 1))
	_block(grid, _rect(11, 5, 3, 1))
	var disagreements: Array = []
	for x: int in 13:
		for z: int in 13:
			var footprint: Array = _rect(x, z, 2, 2)
			var fast: bool = NavPlacement.preserves_connectivity(grid, footprint)
			var slow: bool = grid.placement_preserves_connectivity(footprint)
			if fast != slow:
				disagreements.append("%s: fast=%s slow=%s" % [Vector2i(x, z), fast, slow])
	assert_eq(disagreements, [], "local check disagrees with the flood fill")


# ─── RULE 2: A SIDE ON THE NAVMESH ──────────────────────────────────────────


func test_a_building_in_the_open_has_four_exposed_sides() -> void:
	var grid := _make_grid(13)
	assert_eq(NavPlacement.exposed_side_count(grid, _rect(4, 4, 2, 2)), 4)
	assert_true(NavPlacement.has_navmesh_side(grid, _rect(4, 4, 2, 2)))


func test_a_walled_in_building_has_none() -> void:
	var grid := _make_grid(13)
	_block(grid, _rect(3, 3, 4, 1))
	_block(grid, _rect(3, 6, 4, 1))
	_block(grid, _rect(3, 4, 1, 2))
	_block(grid, _rect(6, 4, 1, 2))
	assert_eq(NavPlacement.exposed_side_count(grid, _rect(4, 4, 2, 2)), 0)
	assert_false(
		NavPlacement.has_navmesh_side(grid, _rect(4, 4, 2, 2)),
		"a production structure here could train units with nowhere to appear"
	)


func test_half_a_side_is_not_a_side() -> void:
	# A unit leaving a production building needs somewhere to STAND; one cell poking out
	# between two walls is not a way out, so a partly-clear edge does not count.
	var grid := _make_grid(13)
	_block(grid, _rect(3, 3, 4, 1))
	_block(grid, _rect(3, 6, 4, 1))
	_block(grid, _rect(3, 4, 1, 2))
	_block(grid, [Vector2i(6, 4)])  # (6,5) left clear — half of the east side
	assert_eq(NavPlacement.exposed_side_count(grid, _rect(4, 4, 2, 2)), 0)
	grid.set_blocked(Vector2i(6, 4), false)
	assert_eq(
		NavPlacement.exposed_side_count(grid, _rect(4, 4, 2, 2)),
		1,
		"the whole east side clear is a way out"
	)


func test_a_side_onto_a_pocket_does_not_count_for_a_reference_region() -> void:
	# The exposed side has to open onto the ground the OWNER's units are on. A door into a
	# sealed courtyard is not access.
	var grid := _make_grid(15)
	_block(grid, _rect(3, 2, 6, 1))
	_block(grid, _rect(3, 7, 6, 1))
	_block(grid, _rect(3, 3, 1, 4))
	_block(grid, _rect(8, 3, 1, 4))  # courtyard (4..7, 3..6)
	var courtyard: int = grid.component_at(Vector2i(5, 5))
	var outside: int = grid.component_at(Vector2i(12, 12))
	assert_ne(courtyard, outside, "the fixture really is two regions")
	var footprint: Array = _rect(4, 3, 2, 2)  # inside the courtyard
	assert_true(NavPlacement.has_navmesh_side(grid, footprint, courtyard))
	assert_false(
		NavPlacement.has_navmesh_side(grid, footprint, outside),
		"reachable from the courtyard is not reachable from outside it"
	)
	assert_true(
		NavPlacement.has_navmesh_side(grid, footprint),
		"with no reference region, any walkable ground counts"
	)


# ─── THE TWO TOGETHER ───────────────────────────────────────────────────────


func test_accepts_applies_the_access_rule_only_when_asked() -> void:
	var grid := _make_grid(13)
	_block(grid, _rect(3, 3, 4, 1))
	_block(grid, _rect(3, 6, 4, 1))
	_block(grid, _rect(3, 4, 1, 2))
	_block(grid, _rect(6, 4, 1, 2))
	var sealed: Array = _rect(4, 4, 2, 2)
	assert_true(
		NavPlacement.accepts(grid, sealed, false),
		"connectivity alone is happy: filling a sealed pocket removes a region"
	)
	assert_false(
		NavPlacement.accepts(grid, sealed, true),
		"but a structure units must reach may not go there"
	)


func test_an_empty_footprint_is_refused_rather_than_trivially_accepted() -> void:
	var grid := _make_grid(9)
	assert_false(NavPlacement.accepts(grid, [], true))


# ─── RULE 3: THE WIDEST UNIT'S VIEW ─────────────────────────────────────────
# A LARGE unit needs a 3-cell corridor. These fixtures pass rules 1 and 2 — a narrow unit is
# fine — and are refused or accepted by rule 3 alone.

const WIDE: int = NavAgentClass.Size.LARGE


func test_a_wide_unit_accepts_a_building_in_open_ground() -> void:
	var grid := _make_grid(21)
	assert_true(NavPlacement.accepts_for_class(grid, _rect(8, 8, 4, 4), WIDE, true))


## A wall down x = 10 below z = 8; the only way across is the gap above it, which a
## building in that gap narrows.
func _crossing_grid() -> TerrainGrid:
	var grid := _make_grid(21)
	_block(grid, _rect(10, 8, 1, 12))
	return grid


func test_a_two_cell_gap_cuts_a_wide_unit_off() -> void:
	var grid := _crossing_grid()
	var footprint: Array = _rect(8, 2, 5, 6)  # leaves z = 0..1 open
	assert_true(NavPlacement.accepts(grid, footprint), "a narrow unit still gets through")
	assert_false(NavPlacement.accepts_for_class(grid, footprint, WIDE))


func test_a_three_cell_gap_keeps_a_wide_unit_moving() -> void:
	var grid := _crossing_grid()
	assert_true(NavPlacement.accepts_for_class(grid, _rect(8, 3, 5, 5), WIDE))


## A building in the map corner whose only wide approach is its right-hand side; a terrain
## wall at z = 7 leaves the strip below it too narrow for a wide unit.
func _cornered_building_grid() -> TerrainGrid:
	var grid := _make_grid(21)
	_block(grid, _rect(0, 7, 20, 1))
	grid.place_building(_rect(0, 0, 4, 5), RefCounted.new())
	return grid


func test_a_building_may_not_be_sealed_off_from_a_wide_unit() -> void:
	var grid := _cornered_building_grid()
	var footprint: Array = _rect(6, 0, 4, 6)  # a two-cell gap beside it
	assert_true(NavPlacement.accepts(grid, footprint, true), "passable to a narrow unit")
	assert_false(NavPlacement.accepts_for_class(grid, footprint, WIDE, true))


func test_a_three_cell_gap_keeps_the_building_reachable() -> void:
	var grid := _cornered_building_grid()
	assert_true(NavPlacement.accepts_for_class(grid, _rect(7, 0, 4, 6), WIDE, true))
