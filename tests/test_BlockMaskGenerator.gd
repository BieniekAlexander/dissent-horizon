extends GutTest

## Tests for BlockMaskGenerator.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_BlockMaskGenerator.gd
##
## The producer places impassable blobs on passable terrain while guaranteeing
## the remaining passable surface stays a single connected component.

const WIDTH: int = 30
const DEPTH: int = 30
const MAX_SLOPE_DIFF: float = 0.5


func _heights(a_seed_val: int) -> PackedFloat32Array:
	var gen := GraphPlateauHeightmapGenerator.new()
	gen.width = WIDTH
	gen.depth = DEPTH
	gen.region_count = 14
	gen.height_levels = 3
	gen.height_step = 1.0
	gen.ramp_half_width = 2.5
	gen.seed = a_seed_val
	return gen.generate()


func _make_mask(a_seed_val: int, a_flat_only: bool = true) -> Dictionary:
	var heights: PackedFloat32Array = _heights(a_seed_val)
	var bm := BlockMaskGenerator.new()
	bm.seed = a_seed_val
	bm.flat_only = a_flat_only
	var mask: PackedByteArray = bm.generate(heights, WIDTH, DEPTH)
	return {"heights": heights, "mask": mask}


func _cell_passable(a_h: PackedFloat32Array, a_x: int, a_z: int) -> bool:
	var h00: float = a_h[a_z * WIDTH + a_x]
	var h10: float = a_h[a_z * WIDTH + a_x + 1]
	var h01: float = a_h[(a_z + 1) * WIDTH + a_x]
	var h11: float = a_h[(a_z + 1) * WIDTH + a_x + 1]
	return (
		(maxf(maxf(h00, h10), maxf(h01, h11)) - minf(minf(h00, h10), minf(h01, h11)))
		<= MAX_SLOPE_DIFF
	)


func _cell_flat(a_h: PackedFloat32Array, a_x: int, a_z: int) -> bool:
	var h00: float = a_h[a_z * WIDTH + a_x]
	var h10: float = a_h[a_z * WIDTH + a_x + 1]
	var h01: float = a_h[(a_z + 1) * WIDTH + a_x]
	var h11: float = a_h[(a_z + 1) * WIDTH + a_x + 1]
	return is_equal_approx(h00, h10) and is_equal_approx(h10, h01) and is_equal_approx(h01, h11)


## Components of (passable AND not blocked).
func _passable_unblocked_components(a_h: PackedFloat32Array, a_mask: PackedByteArray) -> int:
	var gw: int = WIDTH - 1
	var gh: int = DEPTH - 1
	var seen: PackedByteArray = PackedByteArray()
	seen.resize(gw * gh)
	var components: int = 0
	for z: int in gh:
		for x: int in gw:
			var idx: int = z * gw + x
			if _cell_passable(a_h, x, z) and a_mask[idx] == 0 and seen[idx] == 0:
				components += 1
				var stack: Array = [Vector2i(x, z)]
				seen[idx] = 1
				while not stack.is_empty():
					var c: Vector2i = stack.pop_back()
					for d: Vector2i in [
						Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
					]:
						var nx: int = c.x + d.x
						var nz: int = c.y + d.y
						if nx >= 0 and nx < gw and nz >= 0 and nz < gh:
							var ni: int = nz * gw + nx
							if _cell_passable(a_h, nx, nz) and a_mask[ni] == 0 and seen[ni] == 0:
								seen[ni] = 1
								stack.append(Vector2i(nx, nz))
	return components


func _blocked_count(a_mask: PackedByteArray) -> int:
	var n: int = 0
	for b: int in a_mask:
		if b != 0:
			n += 1
	return n


func test_mask_is_cell_sized():
	var r: Dictionary = _make_mask(1)
	assert_eq(r["mask"].size(), (WIDTH - 1) * (DEPTH - 1), "mask is one byte per cell")


func test_produces_some_blocks():
	var r: Dictionary = _make_mask(42)
	assert_gt(_blocked_count(r["mask"]), 0, "should block at least some cells")


func test_blocks_are_flat_passable_when_flat_only():
	var r: Dictionary = _make_mask(42, true)
	var h: PackedFloat32Array = r["heights"]
	var mask: PackedByteArray = r["mask"]
	var gw: int = WIDTH - 1
	for z: int in DEPTH - 1:
		for x: int in gw:
			if mask[z * gw + x] != 0:
				assert_true(
					_cell_passable(h, x, z), "blocked cell (%d,%d) must have been passable" % [x, z]
				)
				assert_true(
					_cell_flat(h, x, z),
					"blocked cell (%d,%d) must be flat under flat_only" % [x, z]
				)


func test_passable_surface_connected_after_blocks():
	# The whole point: blocks must never strand part of the map.
	for seed_val: int in [0, 1, 7, 42, 99, 123, 777]:
		var r: Dictionary = _make_mask(seed_val)
		assert_eq(
			_passable_unblocked_components(r["heights"], r["mask"]),
			1,
			"seed %d: passable-minus-blocked must stay a single component" % seed_val
		)


func test_deterministic():
	var a: Dictionary = _make_mask(42)
	var b: Dictionary = _make_mask(42)
	assert_eq(a["mask"], b["mask"], "same seed must produce the same mask")
