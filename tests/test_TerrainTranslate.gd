extends GutTest

## Tests for TerrainData's region-translation primitives and the editor-time entity-support
## predicate (see docs/terrain-translate.md).
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_TerrainTranslate.gd -gexit

const W: int = 7  # 7x7 corners -> 6x6 = 36 cells

## Sized so the derived grid is exactly W: 2 + 3 + 2 = 7.
const PLAY_SIZE: Vector2i = Vector2i(2, 3)

## Catalog indices built by _make_catalog.
const OPEN: int = 0
const WATER: int = 1   # a second material, so a moved cell is distinguishable
const CLIFF: int = 2   # a third


func _make_catalog() -> TerrainTileCatalog:
	var open := TileType.new()
	open.name = "Open"

	var water := TileType.new()
	water.name = "Water"

	var cliff := TileType.new()
	cliff.name = "Cliff"

	var catalog := TerrainTileCatalog.new()
	catalog.types = [open, water, cliff]
	return catalog


## A flat WxW-corner TerrainData with an all-Open (empty) tile layer.
##
## `dimensions` is derived, not authored: the grid is play_size.x + play_size.y + 2 per side,
## so PLAY_SIZE below is the only thing that sizes this to W. Play bounds are always in force,
## which is why the cells the support tests probe sit near the middle — the grid's (x, z)
## corners are outside the play diamond by construction.
func _make_data() -> TerrainData:
	var data := TerrainData.new()
	data.play_size = PLAY_SIZE
	assert(data.dimensions == Vector2i(W, W))
	var heights := PackedFloat32Array()
	heights.resize(W * W)  # all zeros
	data.heights = heights
	data.catalog = _make_catalog()
	return data


func _height_at(a_data: TerrainData, a_x: int, a_z: int) -> float:
	return a_data.heights[a_z * a_data.dimensions.x + a_x]


func _set_height(a_data: TerrainData, a_x: int, a_z: int, a_v: float) -> void:
	var h: PackedFloat32Array = a_data.heights
	h[a_z * a_data.dimensions.x + a_x] = a_v
	a_data.heights = h


func _set_tile(a_data: TerrainData, a_x: int, a_z: int, a_type: int) -> void:
	var t: PackedByteArray = a_data.tile_types
	if t.size() != a_data.grid_width() * a_data.grid_depth():
		t.resize(a_data.grid_width() * a_data.grid_depth())
	t[a_z * a_data.grid_width() + a_x] = a_type
	a_data.tile_types = t


#region translate_region — heights
func test_translate_moves_the_corner_block():
	var data := _make_data()
	_set_height(data, 1, 1, 3.0)

	var out: Dictionary = data.translate_region(Rect2i(1, 1, 2, 2), Vector2i(4, 4))
	data.heights = out["heights"]

	assert_eq(_height_at(data, 4, 4), 3.0, "the raised corner landed at the destination")
	assert_eq(_height_at(data, 1, 1), 3.0, "a copy leaves the source intact")


func test_translate_copies_one_more_corner_than_cells():
	# A 2x2 CELL region spans 3x3 CORNERS; the far corner must come along.
	var data := _make_data()
	for j: int in 3:
		for i: int in 3:
			_set_height(data, i, j, 1.5)

	var out: Dictionary = data.translate_region(Rect2i(0, 0, 2, 2), Vector2i(4, 4))
	data.heights = out["heights"]

	assert_eq(_height_at(data, 6, 6), 1.5, "the (w+1, h+1) corner was copied too")
	assert_eq(_height_at(data, 4, 4), 1.5)


func test_translate_reads_pre_move_data_when_overlapping():
	# Nudging a region by one cell: the destination overlaps the source, so a naive
	# in-place write would smear the leading edge across the whole region.
	var data := _make_data()
	_set_height(data, 0, 0, 2.0)

	var out: Dictionary = data.translate_region(Rect2i(0, 0, 3, 3), Vector2i(1, 0))
	data.heights = out["heights"]

	assert_eq(_height_at(data, 1, 0), 2.0, "moved one cell right")
	assert_eq(_height_at(data, 2, 0), 0.0, "not smeared onward")


func test_cut_clears_only_the_part_the_destination_misses():
	var data := _make_data()
	for j: int in 4:
		for i: int in 4:
			_set_height(data, i, j, 4.0)

	# Move a 3x3-cell region right by 1 — source and destination overlap.
	var out: Dictionary = data.translate_region(
		Rect2i(0, 0, 3, 3), Vector2i(1, 0),
		TerrainData.LAYER_ALL, TerrainData.RegionTransform.NONE, true
	)
	data.heights = out["heights"]

	assert_eq(_height_at(data, 0, 0), 0.0, "the vacated column was cleared")
	assert_eq(_height_at(data, 1, 0), 4.0, "the overlap kept what was just written")


func test_flip_x_reverses_the_region():
	var data := _make_data()
	_set_height(data, 0, 0, 5.0)

	# 2 cells wide -> 3 corners; corner 0 maps to corner 2 of the destination.
	var out: Dictionary = data.translate_region(
		Rect2i(0, 0, 2, 2), Vector2i(4, 0),
		TerrainData.LAYER_ALL, TerrainData.RegionTransform.FLIP_X
	)
	data.heights = out["heights"]

	assert_eq(_height_at(data, 6, 0), 5.0, "flipped to the far corner of the destination")
	assert_eq(_height_at(data, 4, 0), 0.0)


func test_destination_out_of_bounds_is_clipped_not_rejected():
	var data := _make_data()
	_set_height(data, 0, 0, 7.0)
	_set_height(data, 1, 0, 8.0)

	var out: Dictionary = data.translate_region(Rect2i(0, 0, 2, 2), Vector2i(W - 1, 0))
	data.heights = out["heights"]

	assert_eq(_height_at(data, W - 1, 0), 7.0, "the in-bounds part still landed")
	assert_eq(data.heights.size(), W * W, "the layer kept its size")
#endregion


#region translate_region — tile types
func test_translate_moves_tile_types():
	var data := _make_data()
	_set_tile(data, 1, 1, WATER)

	var out: Dictionary = data.translate_region(Rect2i(1, 1, 1, 1), Vector2i(4, 4))
	data.tile_types = out["tile_types"]

	assert_eq(data.tile_at(Vector2i(4, 4)), WATER)
	assert_eq(data.tile_at(Vector2i(1, 1)), WATER, "copy left the source")


func test_all_open_tile_layer_stays_empty():
	# The "empty means all-Open" invariant must survive a region op, or every translate
	# would materialize a full zero-filled layer into the saved resource.
	var data := _make_data()
	assert_true(data.tile_types.is_empty(), "precondition: nothing painted yet")

	var out: Dictionary = data.translate_region(Rect2i(0, 0, 3, 3), Vector2i(2, 2))

	assert_true((out["tile_types"] as PackedByteArray).is_empty(),
		"an all-Open result compacts back to empty")


func test_layer_mask_leaves_the_other_layer_alone():
	var data := _make_data()
	_set_height(data, 1, 1, 9.0)
	_set_tile(data, 1, 1, WATER)

	var out: Dictionary = data.translate_region(
		Rect2i(1, 1, 1, 1), Vector2i(4, 4), TerrainData.LAYER_HEIGHTS
	)
	data.heights = out["heights"]
	data.tile_types = out["tile_types"]

	assert_eq(_height_at(data, 4, 4), 9.0, "heights moved")
	assert_eq(data.tile_at(Vector2i(4, 4)), OPEN, "tile types did not")
#endregion


#region shift_all
func test_shift_clip_default_fills_the_exposed_strip():
	var data := _make_data()
	for j: int in W:
		for i: int in W:
			_set_height(data, i, j, 2.0)

	var out: Dictionary = data.shift_all(Vector2i(2, 0), TerrainData.LAYER_ALL,
		TerrainData.EdgePolicy.CLIP)
	data.heights = out["heights"]

	assert_eq(_height_at(data, 0, 0), 0.0, "newly exposed column default-filled")
	assert_eq(_height_at(data, 1, 0), 0.0)
	assert_eq(_height_at(data, 2, 0), 2.0, "content shifted right by 2")


func test_shift_extend_edge_repeats_the_boundary():
	var data := _make_data()
	for j: int in W:
		for i: int in W:
			_set_height(data, i, j, 2.0)

	var out: Dictionary = data.shift_all(Vector2i(2, 0), TerrainData.LAYER_ALL,
		TerrainData.EdgePolicy.EXTEND_EDGE)
	data.heights = out["heights"]

	assert_eq(_height_at(data, 0, 0), 2.0, "exposed strip continues the terrain")


func test_shift_wrap_is_invertible():
	var data := _make_data()
	_set_height(data, 0, 0, 3.0)
	_set_height(data, 3, 2, 6.0)
	var before: PackedFloat32Array = data.heights.duplicate()

	var out: Dictionary = data.shift_all(Vector2i(3, 1), TerrainData.LAYER_ALL,
		TerrainData.EdgePolicy.WRAP)
	data.heights = out["heights"]
	assert_ne(data.heights, before, "the shift actually moved something")

	out = data.shift_all(Vector2i(-3, -1), TerrainData.LAYER_ALL, TerrainData.EdgePolicy.WRAP)
	data.heights = out["heights"]
	assert_eq(data.heights, before, "shifting back restores the map exactly")


func test_zero_offset_shift_is_a_no_op():
	var data := _make_data()
	_set_height(data, 2, 2, 1.0)
	var before: PackedFloat32Array = data.heights.duplicate()

	var out: Dictionary = data.shift_all(Vector2i.ZERO)

	assert_eq(out["heights"] as PackedFloat32Array, before)


func test_shift_moves_tile_types_with_the_heights():
	var data := _make_data()
	_set_tile(data, 0, 0, WATER)

	var out: Dictionary = data.shift_all(Vector2i(2, 2), TerrainData.LAYER_ALL,
		TerrainData.EdgePolicy.CLIP)
	data.tile_types = out["tile_types"]

	assert_eq(data.tile_at(Vector2i(2, 2)), WATER)
	assert_eq(data.tile_at(Vector2i(0, 0)), OPEN, "the vacated cell reads as Open")
#endregion


#region plugin
func test_terrain_brush_plugin_script_compiles():
	# The Region-mode UI lives in an EditorPlugin that no other test touches, so a syntax or
	# type error there would otherwise only surface when someone opens the editor.
	var script: GDScript = load("res://addons/terrain_brush/terrain_brush_plugin.gd")
	assert_not_null(script, "the terrain brush plugin script compiles")
#endregion


#region cell_supports_entity
func test_flat_open_ground_supports_an_entity():
	var data := _make_data()
	assert_true(data.cell_supports_entity(Vector2i(2, 2)))
	assert_true(data.cell_is_flat(Vector2i(2, 2)))


func test_out_of_bounds_supports_nothing():
	var data := _make_data()
	assert_false(data.cell_supports_entity(Vector2i(-1, 0)))
	assert_false(data.cell_supports_entity(Vector2i(W, W)))


func test_a_ground_material_never_blocks_support():
	var data := _make_data()
	_set_tile(data, 2, 2, WATER)
	assert_true(data.cell_supports_entity(Vector2i(2, 2)), "a material is art, never passability")


func test_void_cell_does_not_support():
	var data := _make_data()
	var voids := PackedByteArray()
	voids.resize(data.grid_width() * data.grid_depth())
	voids[2 * data.grid_width() + 2] = 1
	data.void_cells = voids
	assert_false(data.cell_supports_entity(Vector2i(2, 2)), "a mesh hole holds nothing up")
	assert_false(data.is_cell_in_play(Vector2i(2, 2)), "void is out of play")
	assert_eq(data.blocked_mask()[2 * data.grid_width() + 2], 1, "and blocked")


func test_steep_cell_does_not_support():
	var data := _make_data()
	# One corner raised past the slope tolerance makes its four cells too steep.
	_set_height(data, 3, 3, TerrainGrid.MAX_SLOPE_DIFF + 1.0)

	assert_false(data.cell_supports_entity(Vector2i(3, 3)), "spread exceeds MAX_SLOPE_DIFF")
	# (1, 2), not the (0, 0) corner: corner cells are out of play on every derived grid.
	assert_true(data.cell_supports_entity(Vector2i(1, 2)), "a distant flat cell is fine")


func test_gentle_slope_still_supports_but_is_not_flat():
	var data := _make_data()
	# Exactly at the tolerance: traversable, but not level enough to build on.
	_set_height(data, 3, 3, TerrainGrid.MAX_SLOPE_DIFF)

	assert_true(data.cell_supports_entity(Vector2i(3, 3)), "at tolerance is still passable")
	assert_false(data.cell_is_flat(Vector2i(3, 3)), "but structures need perfectly level ground")
#endregion
