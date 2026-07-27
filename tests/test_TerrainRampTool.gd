extends GutTest

## Tests for the terrain brush's Ramp tool (TerrainBrushPlugin._stamp_ramp).
##
## A ramp exists to make one level reachable from another, so the properties that matter are
## GAMEPLAY ones: its ends must meet the existing ground with no step, and its slope must come
## out under TerrainGrid.MAX_SLOPE_DIFF so units can actually walk up it. A ramp that looks
## right but reads as impassable is the failure this pins.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_TerrainRampTool.gd

const PLUGIN := preload("res://addons/terrain_brush/terrain_brush_plugin.gd")
const W: int = 40


func _terrain() -> TerrainData:
	var td := TerrainData.new()
	# play_size 19 -> a 40x40 corner grid.
	td.play_size = Vector2i(19, 19)
	return td


## Flat at `low`, except x >= step_x which sits at `high` — two levels to bridge.
func _two_levels(a_td: TerrainData, a_low: float, a_high: float, a_step_x: int) -> PackedFloat32Array:
	var h := PackedFloat32Array()
	h.resize(a_td.map_width() * a_td.map_depth())
	for z: int in a_td.map_depth():
		for x: int in a_td.map_width():
			h[z * a_td.map_width() + x] = a_high if x >= a_step_x else a_low
	return h


func _at(a_td: TerrainData, a_h: PackedFloat32Array, a_x: int, a_z: int) -> float:
	return a_h[a_z * a_td.map_width() + a_x]


func test_grid_is_the_expected_size():
	var td := _terrain()
	assert_eq(td.map_width(), W)
	assert_eq(td.map_depth(), W)


## The core behaviour: heights interpolate linearly along the drag.
func test_ramp_interpolates_between_its_endpoint_heights():
	var td := _terrain()
	var h: PackedFloat32Array = _two_levels(td, 0.0, 6.0, 20)
	PLUGIN._stamp_ramp(td, h, Vector2i(8, 20), Vector2i(32, 20), 3.0, 0.0)

	var a: float = _at(td, h, 9, 20)
	var mid: float = _at(td, h, 20, 20)
	var b: float = _at(td, h, 31, 20)
	assert_lt(a, mid, "rises along the drag")
	assert_lt(mid, b)
	# Midpoint should sit near the average of the two ends.
	assert_almost_eq(mid, (a + b) * 0.5, 0.6, "linear, not stepped")


## No cliff at either end — that is what "connects two levels" means.
func test_ramp_ends_match_the_ground_they_meet():
	var td := _terrain()
	var before: PackedFloat32Array = _two_levels(td, 0.0, 6.0, 20)
	var h: PackedFloat32Array = before.duplicate()
	PLUGIN._stamp_ramp(td, h, Vector2i(8, 20), Vector2i(32, 20), 3.0, 0.0)
	# Cell (8,20) is on the low shelf, (28,20) on the high one; the ramp should start and end
	# at those levels rather than jumping to them.
	assert_almost_eq(_at(td, h, 8, 20), 0.0, 0.35, "low end meets the low ground")
	assert_almost_eq(_at(td, h, 32, 20), 6.0, 0.35, "high end meets the high ground")


## The point of the tool: the result has to be walkable.
func test_a_long_ramp_is_walkable():
	var td := _terrain()
	td.heights = _two_levels(td, 0.0, 6.0, 20)
	var h: PackedFloat32Array = td.heights.duplicate()
	PLUGIN._stamp_ramp(td, h, Vector2i(8, 20), Vector2i(32, 20), 3.0, 0.0)
	td.heights = h
	# Every cell along the ramp's spine must be under the slope limit.
	var steep: int = 0
	for x: int in range(9, 32):
		if td.cell_height_spread(Vector2i(x, 20)) > TerrainGrid.MAX_SLOPE_DIFF:
			steep += 1
	assert_eq(steep, 0, "a 24-cell ramp over 6 units of rise is climbable")


## A short ramp over the same rise is too steep — the tool doesn't magically make it passable,
## and the author needs to know that.
func test_a_short_ramp_is_too_steep():
	var td := _terrain()
	td.heights = _two_levels(td, 0.0, 6.0, 20)
	var h: PackedFloat32Array = td.heights.duplicate()
	PLUGIN._stamp_ramp(td, h, Vector2i(18, 20), Vector2i(22, 20), 3.0, 0.0)
	td.heights = h
	var steep: int = 0
	for x: int in range(18, 22):
		if td.cell_height_spread(Vector2i(x, 20)) > TerrainGrid.MAX_SLOPE_DIFF:
			steep += 1
	assert_gt(steep, 0, "4 cells cannot absorb 6 units of rise")


func test_ramp_respects_its_width():
	var td := _terrain()
	var before: PackedFloat32Array = _two_levels(td, 0.0, 6.0, 20)
	var h: PackedFloat32Array = before.duplicate()
	PLUGIN._stamp_ramp(td, h, Vector2i(8, 20), Vector2i(32, 20), 3.0, 0.0)
	# Well outside the half-width, nothing moved.
	for z: int in [10, 30]:
		assert_almost_eq(_at(td, h, 18, z), _at(td, before, 18, z), 0.0001,
			"row %d is outside the ramp" % z)


func test_feather_softens_the_long_sides():
	var td := _terrain()
	var hard: PackedFloat32Array = _two_levels(td, 0.0, 6.0, 20)
	var soft: PackedFloat32Array = hard.duplicate()
	PLUGIN._stamp_ramp(td, hard, Vector2i(8, 20), Vector2i(32, 20), 3.0, 0.0)
	PLUGIN._stamp_ramp(td, soft, Vector2i(8, 20), Vector2i(32, 20), 3.0, 5.0)
	# Just outside the hard half-width: untouched without feather, pulled toward the ramp with.
	var x: int = 12
	var z: int = 25
	assert_almost_eq(_at(td, hard, x, z), 0.0, 0.0001, "no feather leaves it alone")
	assert_gt(_at(td, soft, x, z), 0.0, "feather reaches past the half-width")


func test_zero_length_drag_does_nothing():
	var td := _terrain()
	var before: PackedFloat32Array = _two_levels(td, 0.0, 6.0, 20)
	var h: PackedFloat32Array = before.duplicate()
	PLUGIN._stamp_ramp(td, h, Vector2i(12, 20), Vector2i(12, 20), 3.0, 0.0)
	for i: int in before.size():
		assert_almost_eq(h[i], before[i], 0.0001)
