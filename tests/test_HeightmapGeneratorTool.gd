extends GutTest

## Tests for HeightmapGeneratorTool's seed handling (random_next_seed).
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_HeightmapGeneratorTool.gd

const W: int = 24  # small map for speed


# A minimal generator with NO `seed` property, to exercise the seedless path.
class SeedlessGen extends HeightmapGenerator:
	func generate() -> PackedFloat32Array:
		var d := PackedFloat32Array()
		d.resize(width * depth)
		d.fill(1.0)
		return d


func _make_shape() -> HeightMapShape3D:
	var s := HeightMapShape3D.new()
	s.map_width = W
	s.map_depth = W
	var d := PackedFloat32Array()
	d.resize(W * W)
	s.map_data = d
	return s


func _graph_gen() -> GraphPlateauHeightmapGenerator:
	var g := GraphPlateauHeightmapGenerator.new()
	# The generator's width/depth now drive the output size (the shape is sized to
	# match), so set them to the small test dimensions.
	g.width = W
	g.depth = W
	g.region_count = 6
	g.height_levels = 3
	g.ramp_half_width = 3.0
	g.seed = 0
	return g


func _make_tool(gen: HeightmapGenerator) -> HeightmapGeneratorTool:
	var t := HeightmapGeneratorTool.new()
	add_child_autofree(t)
	var mg := HeightmapMeshGenerator.new()
	add_child_autofree(mg)
	t.mesh_generator = mg
	t.generator = gen
	t.shape = _make_shape()
	mg.shape = t.shape
	return t


func test_random_next_seed_rolls_and_writes_back_seed():
	var g := _graph_gen()
	var t := _make_tool(g)
	t.random_next_seed = true
	g.seed = 0
	t._do_generate()
	var s1: int = g.seed
	assert_ne(s1, 0, "a random seed should have been rolled and stored")
	assert_eq(t.shape.map_data.size(), W * W, "the map was generated")

	t._do_generate()
	assert_ne(g.seed, s1, "each random run rolls a different seed")


func test_fixed_seed_unchanged_when_flag_false():
	var g := _graph_gen()
	var t := _make_tool(g)
	t.random_next_seed = false
	g.seed = 12345
	t._do_generate()
	assert_eq(g.seed, 12345, "seed is left untouched when random_next_seed is false")


func test_fixed_seed_is_deterministic():
	var g1 := _graph_gen()
	g1.seed = 777
	var t1 := _make_tool(g1)
	t1.random_next_seed = false
	t1._do_generate()

	var g2 := _graph_gen()
	g2.seed = 777
	var t2 := _make_tool(g2)
	t2.random_next_seed = false
	t2._do_generate()

	assert_eq(t1.shape.map_data, t2.shape.map_data, "same fixed seed → same map")


func test_random_seed_with_auto_generate_does_not_recurse():
	# auto_generate_on_change connects the generator's `changed` signal to
	# _do_generate; writing the rolled seed emits `changed`.  The re-entrancy
	# guard must stop that from recursing.  Reaching the assert == no hang.
	var g := _graph_gen()
	var t := _make_tool(g)
	t.auto_generate_on_change = true
	t.random_next_seed = true
	t._do_generate()
	assert_eq(t.shape.map_data.size(), W * W, "completed a single pass without recursing")


func test_seedless_generator_is_safe():
	var g := SeedlessGen.new()
	var t := _make_tool(g)
	t.random_next_seed = true
	t._do_generate()  # generator has no seed → silent no-op, must not crash
	assert_eq(t.shape.map_data[0], 1.0, "seedless generator still produced output")
