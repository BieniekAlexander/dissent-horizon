extends GutTest

## Tests for the terrain's derived shading inputs (TerrainShading), the grid mesh's normals, and
## the default lighting a scenario falls back to. The PICTURE is reviewed with
## tools/terrain_visuals/visual_preview.tscn; these pin the facts the picture depends on.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_TerrainShading.gd \
##     -gdir=res://tests/none -gexit

const _PLAY: Vector2i = Vector2i(6, 6)


func _terrain(a_fill: float) -> TerrainData:
	var td := TerrainData.new()
	td.play_size = _PLAY
	var heights := PackedFloat32Array()
	heights.resize(td.map_width() * td.map_depth())
	heights.fill(a_fill)
	td.heights = heights
	return td


func test_height_range_spans_the_heights() -> void:
	assert_eq(TerrainShading.height_range(PackedFloat32Array([3.0, -1.0, 7.5])), Vector2(-1.0, 7.5))
	assert_eq(TerrainShading.height_range(PackedFloat32Array()), Vector2.ZERO)


func test_the_height_texture_is_one_texel_per_corner() -> void:
	var td: TerrainData = _terrain(2.0)
	var texture: ImageTexture = TerrainShading.height_texture(td)
	assert_eq(texture.get_size(), Vector2(td.map_width(), td.map_depth()))
	assert_almost_eq(texture.get_image().get_pixel(3, 3).r, 2.0, 0.0001)


func test_a_malformed_heights_layer_has_no_texture() -> void:
	var td: TerrainData = _terrain(2.0)
	td.heights = PackedFloat32Array([1.0])
	assert_null(TerrainShading.height_texture(td))
	var material := ShaderMaterial.new()
	TerrainShading.push_terrain_uniforms(material, td, Vector2.ZERO)
	assert_eq(material.get_shader_parameter("has_heights"), 0.0)


## Regression: the quad-per-cell mesh shipped with normals pointing INTO the ground, so under
## any sun every lit terrain material rendered black.
func test_the_grid_mesh_faces_up() -> void:
	var td: TerrainData = _terrain(1.0)
	var generator := HeightmapMeshGenerator.new()
	generator.terrain_data_override = td
	generator.shape = td.to_height_shape()
	generator.build()
	var normals: PackedVector3Array = generator.mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
	assert_gt(normals.size(), 0)
	for normal: Vector3 in normals:
		assert_gt(normal.y, 0.99)
	generator.free()


func test_an_unlit_scenario_gets_the_default_rig() -> void:
	var scenario := Scenario.new()
	scenario._ensure_lighting()
	assert_eq(scenario.find_children("*", "DirectionalLight3D", true, false).size(), 2,
		"key and fill")
	scenario.free()


func test_a_scenario_that_lights_itself_keeps_its_own_light() -> void:
	var scenario := Scenario.new()
	var sun := DirectionalLight3D.new()
	scenario.add_child(sun)
	scenario._ensure_lighting()
	assert_eq(scenario.find_children("*", "DirectionalLight3D", true, false), [sun])
	scenario.free()
