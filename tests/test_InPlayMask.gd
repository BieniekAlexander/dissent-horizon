extends GutTest

## TerrainData.in_play_mask is is_cell_in_play over every cell, memoized: it must agree with the
## single-cell rule, follow a change to play_size or void_cells, and hand out a copy a caller
## may edit.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_InPlayMask.gd -gexit

const PLAY_SIZE := Vector2i(6, 4)


func _terrain() -> TerrainData:
	var terrain := TerrainData.new()
	terrain.play_size = PLAY_SIZE
	return terrain


func _agrees_with_each_cell(a_terrain: TerrainData) -> bool:
	var mask: PackedByteArray = a_terrain.in_play_mask()
	var gw: int = a_terrain.grid_width()
	for z: int in a_terrain.grid_depth():
		for x: int in gw:
			if (mask[z * gw + x] != 0) != a_terrain.is_cell_in_play(Vector2i(x, z)):
				return false
	return true


func test_it_is_the_single_cell_rule_over_the_grid() -> void:
	var terrain: TerrainData = _terrain()
	var mask: PackedByteArray = terrain.in_play_mask()
	assert_eq(mask.size(), terrain.grid_width() * terrain.grid_depth())
	assert_true(_agrees_with_each_cell(terrain))
	assert_true(mask.has(0) and mask.has(1), "the fixture has cells on both sides of the edge")


func test_it_follows_a_void_cell() -> void:
	var terrain: TerrainData = _terrain()
	terrain.in_play_mask()
	var gw: int = terrain.grid_width()
	var centre := Vector2i(gw / 2, terrain.grid_depth() / 2)
	assert_true(terrain.is_cell_in_play(centre), "guards the fixture")
	var voids := PackedByteArray()
	voids.resize(gw * terrain.grid_depth())
	voids[centre.y * gw + centre.x] = 1
	terrain.void_cells = voids
	assert_eq(terrain.in_play_mask()[centre.y * gw + centre.x], 0)
	assert_true(_agrees_with_each_cell(terrain))


func test_it_follows_the_play_size() -> void:
	var terrain: TerrainData = _terrain()
	terrain.in_play_mask()
	terrain.play_size = PLAY_SIZE + Vector2i(2, 2)
	assert_eq(terrain.in_play_mask().size(), terrain.grid_width() * terrain.grid_depth())
	assert_true(_agrees_with_each_cell(terrain))


func test_editing_the_returned_mask_leaves_the_memo_alone() -> void:
	var terrain: TerrainData = _terrain()
	var mask: PackedByteArray = terrain.in_play_mask()
	mask.fill(0)
	assert_true(_agrees_with_each_cell(terrain))


func test_the_blocked_mask_is_its_complement() -> void:
	var terrain: TerrainData = _terrain()
	var in_play: PackedByteArray = terrain.in_play_mask()
	var blocked: PackedByteArray = terrain.blocked_mask()
	for i: int in in_play.size():
		assert_eq(blocked[i], 1 - in_play[i])
