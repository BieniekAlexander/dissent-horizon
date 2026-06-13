extends GutTest

## Tests for GraphPlateauHeightmapGenerator.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_GraphPlateauHeightmapGenerator.gd
##
## The generator produces Red Alert 2-style terrain: flat plateaus at discrete
## tiers, hard cliffs, and ramps.  The properties that matter for playability and
## that were hard to get right are:
##   1. Output size matches width*depth.
##   2. The passable surface is ONE connected component (the repair guarantee).
##   3. Plateaus exist (a meaningful fraction of cells are perfectly flat).
##   4. Generation is deterministic for a fixed seed.
##
## "Passable" mirrors TerrainGrid: a cell is passable when its four corner heights
## span no more than MAX_SLOPE_DIFF (0.5).

const WIDTH: int = 30
const DEPTH: int = 30
const MAX_SLOPE_DIFF: float = 0.5

func _make(seed_val: int, height_levels: int = 3) -> GraphPlateauHeightmapGenerator:
	var gen := GraphPlateauHeightmapGenerator.new()
	gen.width = WIDTH
	gen.depth = DEPTH
	gen.region_count = 14
	gen.height_levels = height_levels
	gen.height_step = 1.0
	gen.ramp_run = 4
	gen.ramp_half_width = 2.5
	gen.seed = seed_val
	return gen


func _cell_passable(data: PackedFloat32Array, x: int, z: int) -> bool:
	var h00: float = data[z * WIDTH + x]
	var h10: float = data[z * WIDTH + x + 1]
	var h01: float = data[(z + 1) * WIDTH + x]
	var h11: float = data[(z + 1) * WIDTH + x + 1]
	return (maxf(maxf(h00, h10), maxf(h01, h11)) - minf(minf(h00, h10), minf(h01, h11))) <= MAX_SLOPE_DIFF


## Number of connected components in the passable cell grid (4-neighbour).
func _component_count(data: PackedFloat32Array) -> int:
	var gw: int = WIDTH - 1
	var gh: int = DEPTH - 1
	var seen: PackedByteArray = PackedByteArray()
	seen.resize(gw * gh)
	var components: int = 0
	for z: int in gh:
		for x: int in gw:
			if _cell_passable(data, x, z) and seen[z * gw + x] == 0:
				components += 1
				var stack: Array = [Vector2i(x, z)]
				seen[z * gw + x] = 1
				while not stack.is_empty():
					var c: Vector2i = stack.pop_back()
					for d: Vector2i in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
						var nx: int = c.x + d.x
						var nz: int = c.y + d.y
						if nx >= 0 and nx < gw and nz >= 0 and nz < gh \
								and _cell_passable(data, nx, nz) and seen[nz * gw + nx] == 0:
							seen[nz * gw + nx] = 1
							stack.append(Vector2i(nx, nz))
	return components


func test_output_size_matches_dimensions():
	var data: PackedFloat32Array = _make(1).generate()
	assert_eq(data.size(), WIDTH * DEPTH, "one height per heightmap corner")


func test_passable_surface_is_connected_across_seeds():
	# The repair pass must guarantee a single connected component for any seed.
	for seed_val: int in [0, 1, 2, 3, 7, 42, 99, 123, 777, 2024]:
		var data: PackedFloat32Array = _make(seed_val).generate()
		assert_eq(_component_count(data), 1,
			"seed %d: passable surface should be a single connected component" % seed_val)


func test_connected_for_more_tiers():
	# More elevation tiers stress the connectivity guarantee harder.
	for seed_val: int in [0, 5, 13, 42, 100]:
		var data: PackedFloat32Array = _make(seed_val, 5).generate()
		assert_eq(_component_count(data), 1,
			"seed %d (5 tiers): should still be connected" % seed_val)


func test_produces_flat_plateaus():
	# A RA2-style map should be mostly flat plateaus, not all-slope mush.
	var data: PackedFloat32Array = _make(42).generate()
	var gw: int = WIDTH - 1
	var gh: int = DEPTH - 1
	var flat: int = 0
	for z: int in gh:
		for x: int in gw:
			var h00: float = data[z * WIDTH + x]
			var h10: float = data[z * WIDTH + x + 1]
			var h01: float = data[(z + 1) * WIDTH + x]
			var h11: float = data[(z + 1) * WIDTH + x + 1]
			if is_equal_approx(h00, h10) and is_equal_approx(h10, h01) and is_equal_approx(h01, h11):
				flat += 1
	var frac: float = float(flat) / float(gw * gh)
	assert_gt(frac, 0.4, "at least 40%% of cells should be perfectly flat plateau (was %d%%)" % roundi(frac * 100.0))


func test_uses_multiple_elevation_levels():
	# With 3 tiers and the default change chance, a map should use more than one.
	var data: PackedFloat32Array = _make(42).generate()
	var levels_seen: Dictionary = {}
	for h: float in data:
		levels_seen[roundi(h)] = true
	assert_gt(levels_seen.size(), 1, "expected more than one elevation tier in use")


func _slope_cell_count(data: PackedFloat32Array) -> int:
	# Passable but not flat = a ramp cell.
	var gw: int = WIDTH - 1
	var gh: int = DEPTH - 1
	var count: int = 0
	for z: int in gh:
		for x: int in gw:
			var h00: float = data[z * WIDTH + x]
			var h10: float = data[z * WIDTH + x + 1]
			var h01: float = data[(z + 1) * WIDTH + x]
			var h11: float = data[(z + 1) * WIDTH + x + 1]
			var hi: float = maxf(maxf(h00, h10), maxf(h01, h11))
			var lo: float = minf(minf(h00, h10), minf(h01, h11))
			if (hi - lo) <= MAX_SLOPE_DIFF and not is_equal_approx(hi, lo):
				count += 1
	return count


func test_wider_ramps_stay_connected_and_get_wider():
	# Increasing ramp_half_width must keep the map connected (the repair loop has
	# to converge with wider corridors) and produce visibly wider ramps.
	for seed_val: int in [0, 7, 42, 99]:
		var narrow := _make(seed_val)
		narrow.ramp_half_width = 1.5
		var wide := _make(seed_val)
		wide.ramp_half_width = 4.0

		var narrow_data: PackedFloat32Array = narrow.generate()
		var wide_data: PackedFloat32Array = wide.generate()

		assert_eq(_component_count(narrow_data), 1, "seed %d narrow connected" % seed_val)
		assert_eq(_component_count(wide_data), 1, "seed %d wide connected" % seed_val)
		assert_gt(_slope_cell_count(wide_data), _slope_cell_count(narrow_data),
			"seed %d: wider ramp_half_width should yield more ramp cells" % seed_val)


# Generic (size-parameterised) connected-component count for the larger maps.
func _components_dim(data: PackedFloat32Array, w: int, d: int) -> int:
	var gw: int = w - 1
	var gh: int = d - 1
	var seen: PackedByteArray = PackedByteArray()
	seen.resize(gw * gh)
	var passable := func(x: int, z: int) -> bool:
		var h00: float = data[z * w + x]
		var h10: float = data[z * w + x + 1]
		var h01: float = data[(z + 1) * w + x]
		var h11: float = data[(z + 1) * w + x + 1]
		return (maxf(maxf(h00, h10), maxf(h01, h11)) - minf(minf(h00, h10), minf(h01, h11))) <= MAX_SLOPE_DIFF
	var components: int = 0
	for z: int in gh:
		for x: int in gw:
			if passable.call(x, z) and seen[z * gw + x] == 0:
				components += 1
				var stack: Array = [Vector2i(x, z)]
				seen[z * gw + x] = 1
				while not stack.is_empty():
					var c: Vector2i = stack.pop_back()
					for dd: Vector2i in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
						var nx: int = c.x + dd.x
						var nz: int = c.y + dd.y
						if nx >= 0 and nx < gw and nz >= 0 and nz < gh \
								and passable.call(nx, nz) and seen[nz * gw + nx] == 0:
							seen[nz * gw + nx] = 1
							stack.append(Vector2i(nx, nz))
	return components


func test_large_map_with_density_is_connected():
	# cells_per_region derives the region count from the area, so a big map gets
	# many same-size plateaus and the connectivity guarantee must still hold.
	var gen := GraphPlateauHeightmapGenerator.new()
	gen.width = 96
	gen.depth = 96
	gen.cells_per_region = 84
	gen.height_levels = 3
	gen.height_step = 1.0
	gen.ramp_half_width = 5.0
	gen.ramp_run = 5
	gen.seed = 7
	var data: PackedFloat32Array = gen.generate()
	assert_eq(data.size(), 96 * 96, "output matches the larger dimensions")
	assert_eq(_components_dim(data, 96, 96), 1, "large density-scaled map stays connected")


func test_cells_per_region_overrides_region_count():
	# With cells_per_region set, region_count is ignored: two very different
	# region_count values must give the same map.
	var a := GraphPlateauHeightmapGenerator.new()
	a.width = 48; a.depth = 48; a.cells_per_region = 100; a.region_count = 2; a.seed = 3
	var b := GraphPlateauHeightmapGenerator.new()
	b.width = 48; b.depth = 48; b.cells_per_region = 100; b.region_count = 999; b.seed = 3
	assert_eq(a.generate(), b.generate(), "cells_per_region should override region_count")


func test_is_deterministic_for_fixed_seed():
	var a: PackedFloat32Array = _make(42).generate()
	var b: PackedFloat32Array = _make(42).generate()
	assert_eq(a, b, "same seed must produce identical heightmaps")


func test_different_seeds_differ():
	var a: PackedFloat32Array = _make(1).generate()
	var b: PackedFloat32Array = _make(2).generate()
	assert_ne(a, b, "different seeds should produce different heightmaps")
