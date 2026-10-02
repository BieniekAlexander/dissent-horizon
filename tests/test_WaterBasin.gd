extends GutTest

## Tests for WaterBasin — the rule that decides which ground a water level covers, and how
## deep. Pure: a TerrainData fixture built here, no Map, no scene tree.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_WaterBasin.gd \
##     -gdir=res://tests/none -gexit
##
## The fixture is a synthetic terrain this file sculpts itself, never a shipped map: what is
## under test is the flood rule, and pinning it against authored content would fail on every
## honest terrain edit while isolating nothing (CLAUDE.md §A unit test does not assert facts
## about authored content).

## A play rectangle small enough to keep the fixture legible and large enough that the centre
## is comfortably inside the play diamond. dimensions is derived: 22 x 22 corners, 21 x 21
## cells, centred on cell (10, 10).
const _PLAY: Vector2i = Vector2i(10, 10)
const _CENTRE: Vector2i = Vector2i(10, 10)
const _GROUND: float = 2.0


## Flat terrain at _GROUND everywhere.
func _terrain() -> TerrainData:
	var td := TerrainData.new()
	td.play_size = _PLAY
	var heights := PackedFloat32Array()
	heights.resize(td.map_width() * td.map_depth())
	heights.fill(_GROUND)
	td.heights = heights
	return td


## Sink the corners of the square block of CELLS spanning [origin, origin + size) to `height`,
## so every cell strictly inside the block is flat at that height.
func _sink(a_td: TerrainData, a_origin: Vector2i, a_size: Vector2i, a_height: float) -> void:
	var heights: PackedFloat32Array = a_td.heights
	var w: int = a_td.map_width()
	for z: int in range(a_origin.y, a_origin.y + a_size.y + 1):
		for x: int in range(a_origin.x, a_origin.x + a_size.x + 1):
			heights[z * w + x] = a_height
	a_td.heights = heights


## Drop one heightmap CORNER, for fixtures that need a hollow narrower than a cell block.
func _lower_corner(a_td: TerrainData, a_corner: Vector2i, a_height: float) -> void:
	var heights: PackedFloat32Array = a_td.heights
	heights[a_corner.y * a_td.map_width() + a_corner.x] = a_height
	a_td.heights = heights


func test_floods_the_pit_and_nothing_above_the_level() -> void:
	var td: TerrainData = _terrain()
	_sink(td, Vector2i(8, 8), Vector2i(4, 4), _GROUND - 1.0)
	var basin: WaterBasin = WaterBasin.fill(td, _CENTRE, _GROUND)
	assert_true(basin.is_valid(), "a sunken pit under the level holds water")
	assert_true(basin.covers_cell(_CENTRE), "the pit floor is covered")
	assert_false(
		basin.covers_cell(Vector2i(2, 2)),
		"ground at the water level is not flooded — dry ground is the wall"
	)


## The seed cell is admitted whatever its height (the level IS the height of the point the
## author is aiming at), but a basin that holds no water anywhere is refused. This is the one
## thing the authoring tool checks before it will create a body.
func test_flat_ground_at_the_level_is_not_a_basin() -> void:
	var td: TerrainData = _terrain()
	var basin: WaterBasin = WaterBasin.fill(td, _CENTRE, _GROUND)
	assert_false(basin.is_valid(), "pointing at flat ground floods nothing")
	assert_eq(basin.covered_cells().size(), 0, "a dry seed cell is not part of the body")


## A level below the ground the cursor is on is likewise nothing: the point of the rule is
## that water cannot be put where the geometry does not hold it.
func test_a_level_under_the_seed_floods_nothing() -> void:
	var td: TerrainData = _terrain()
	_sink(td, Vector2i(8, 8), Vector2i(4, 4), _GROUND - 1.0)
	var basin: WaterBasin = WaterBasin.fill(td, _CENTRE, _GROUND - 2.0)
	assert_false(basin.is_valid(), "a level under the pit floor covers nothing")


func test_a_rim_confines_the_water() -> void:
	var td: TerrainData = _terrain()
	# Two pits of the same depth, separated by a one-cell ridge of untouched ground.
	_sink(td, Vector2i(8, 8), Vector2i(2, 2), _GROUND - 1.0)
	_sink(td, Vector2i(13, 8), Vector2i(2, 2), _GROUND - 1.0)
	var basin: WaterBasin = WaterBasin.fill(td, Vector2i(9, 9), _GROUND)
	assert_true(basin.covers_cell(Vector2i(9, 9)), "the seeded pit floods")
	assert_false(
		basin.covers_cell(Vector2i(14, 9)),
		"the second pit is a separate body — the ridge between them is a wall"
	)


func test_deep_and_shallow_split_at_wade_depth() -> void:
	var td: TerrainData = _terrain()
	var shallow_drop: float = WaterBasin.WADE_DEPTH * 0.5
	var deep_drop: float = WaterBasin.WADE_DEPTH * 2.0
	_sink(td, Vector2i(8, 8), Vector2i(6, 6), _GROUND - shallow_drop)
	_sink(td, Vector2i(10, 10), Vector2i(2, 2), _GROUND - deep_drop)
	var basin: WaterBasin = WaterBasin.fill(td, Vector2i(9, 9), _GROUND)

	assert_true(basin.is_shallow(Vector2i(9, 9)), "half a wade depth is wadeable")
	assert_false(basin.is_deep(Vector2i(9, 9)), "half a wade depth is not deep")
	assert_true(basin.is_deep(Vector2i(11, 11)), "twice a wade depth is deep")
	assert_false(basin.is_shallow(Vector2i(11, 11)), "a deep cell is not also shallow")
	assert_true(
		basin.deep_cells().size() < basin.covered_cells().size(),
		"the deep cells are a subset of the covered ones"
	)


## Exactly WADE_DEPTH is wadeable: the threshold is the deepest water a unit walks through,
## not the shallowest it cannot.
func test_exactly_wade_depth_is_shallow() -> void:
	var td: TerrainData = _terrain()
	_sink(td, Vector2i(8, 8), Vector2i(4, 4), _GROUND - WaterBasin.WADE_DEPTH)
	var basin: WaterBasin = WaterBasin.fill(td, _CENTRE, _GROUND)
	assert_true(basin.is_shallow(_CENTRE), "water exactly WADE_DEPTH deep is still wadeable")
	assert_eq(basin.deep_cells().size(), 0, "nothing leaves the navmesh at exactly wade depth")


## 4-connected, matching how the navmesh stitches cells. Two pits meeting only at a corner
## are two bodies, not one.
##
## Built by dropping two single CORNERS. Corner (10, 10) belongs to cells (9, 9) and (10, 10)
## but to neither of the two cells between them, so dropping (9, 9) and (11, 11) hollows out
## exactly one diagonal pair and leaves their shared orthogonal neighbours dry.
func test_diagonal_contact_does_not_join_two_pits() -> void:
	var td: TerrainData = _terrain()
	_lower_corner(td, Vector2i(9, 9), _GROUND - 1.0)
	_lower_corner(td, Vector2i(11, 11), _GROUND - 1.0)
	var basin: WaterBasin = WaterBasin.fill(td, Vector2i(9, 9), _GROUND)
	assert_true(basin.covers_cell(Vector2i(9, 9)), "the seeded hollow floods")
	assert_false(basin.covers_cell(Vector2i(10, 9)), "the cells between the two are dry")
	assert_false(basin.covers_cell(Vector2i(9, 10)), "the cells between the two are dry")
	assert_false(
		basin.covers_cell(Vector2i(10, 10)), "a hollow touching only at a corner is a separate body"
	)


## The edge of the play area holds water like a wall: the fill stops there rather than
## spilling into the out-of-play corners, and says that it did.
func test_the_play_edge_stops_the_fill() -> void:
	var td: TerrainData = _terrain()
	var basin: WaterBasin = WaterBasin.fill(td, _CENTRE, _GROUND + 10.0)
	assert_true(basin.is_valid(), "a level above everything floods the whole play area")
	assert_true(basin.reaches_play_edge, "a fill that runs out of play area says so")
	for cell: Vector2i in basin.covered_cells():
		assert_true(td.is_cell_in_play(cell), "no covered cell lies outside the play area")


func test_depth_is_never_reported_negative() -> void:
	var td: TerrainData = _terrain()
	var basin: WaterBasin = WaterBasin.fill(td, _CENTRE, _GROUND - 5.0)
	assert_eq(basin.depth_at(_CENTRE), 0.0, "ground above the level reads as dry, not negative")
	assert_eq(basin.depth_at(Vector2i(0, 0)), 0.0, "an uncovered cell reads as dry")


func test_an_out_of_bounds_seed_floods_nothing() -> void:
	var td: TerrainData = _terrain()
	_sink(td, Vector2i(8, 8), Vector2i(4, 4), _GROUND - 1.0)
	var basin: WaterBasin = WaterBasin.fill(td, Vector2i(-1, -1), _GROUND)
	assert_false(basin.is_valid(), "a seed off the grid cannot start a body")


## The colour ramp is keyed to the SAME threshold the navmesh cut uses, so the shoreline a
## player sees is the line their units actually stop at.
func test_the_shade_ramp_is_centred_on_wade_depth() -> void:
	assert_eq(WaterSurfaceMesh.shade_factor(0.0), 0.0, "dry water is fully light")
	assert_almost_eq(
		WaterSurfaceMesh.shade_factor(WaterBasin.WADE_DEPTH),
		0.5,
		0.001,
		"wading depth sits halfway between the two blues"
	)
	assert_eq(
		WaterSurfaceMesh.shade_factor(WaterBasin.WADE_DEPTH * 5.0),
		1.0,
		"well past wading depth is fully dark"
	)
