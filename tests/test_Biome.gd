extends GutTest

## Biome: how a map's look is resolved and pushed into the materials that draw it. Every test
## builds its own Biome; none asserts what a shipped biome contains.


func _biome() -> Biome:
	var biome := Biome.new()
	biome.ground_colors = {"Dirt": Color(0.1, 0.2, 0.3), "Rock": Color(0.4, 0.5, 0.6)}
	biome.fallback_ground = Color(0.9, 0.9, 0.9)
	biome.pond_hues = [Color.RED, Color.GREEN, Color.BLUE] as Array[Color]
	return biome


func _catalog(a_names: Array[String]) -> TerrainTileCatalog:
	var catalog := TerrainTileCatalog.new()
	var types: Array[TileType] = []
	for type_name: String in a_names:
		var type := TileType.new()
		type.name = type_name
		types.append(type)
	catalog.types = types
	return catalog


func test_a_map_naming_no_biome_is_drawn_with_the_default() -> void:
	var map := Map.new()
	assert_eq(map.active_biome(), Biome.default_biome())
	map.free()


func test_a_node_under_a_map_reads_the_maps_biome() -> void:
	var map := Map.new()
	var biome := _biome()
	map.biome = biome
	var child := Node3D.new()
	map.add_child(child)
	assert_eq(Biome.of(child), biome)
	map.free()


func test_a_node_outside_any_map_reads_the_default() -> void:
	var node := Node3D.new()
	assert_eq(Biome.of(node), Biome.default_biome())
	node.free()


func test_tile_colours_follow_type_names_and_fall_back() -> void:
	var colors: PackedColorArray = _biome().tile_color_array(
		_catalog(["Grass", "Dirt", "Rock"] as Array[String]), 8
	)
	assert_eq(colors.size(), 8)
	assert_eq(colors[0], Color(0.9, 0.9, 0.9), "a type the biome does not name")
	assert_eq(colors[1], Color(0.1, 0.2, 0.3))
	assert_eq(colors[2], Color(0.4, 0.5, 0.6))
	assert_eq(colors[7], Color(0.9, 0.9, 0.9), "padding")


func test_tile_colours_without_a_catalog_are_all_fallback() -> void:
	var colors: PackedColorArray = _biome().tile_color_array(null, 4)
	for color: Color in colors:
		assert_eq(color, Color(0.9, 0.9, 0.9))


func test_a_ponds_hue_is_stable_and_from_the_biomes_set() -> void:
	var biome := _biome()
	for cell: Vector2i in [Vector2i(0, 0), Vector2i(3, 7), Vector2i(-2, 40)]:
		var hue: Color = biome.pond_hue(cell)
		assert_has(biome.pond_hues, hue)
		assert_eq(biome.pond_hue(cell), hue, "the same seed cell, the same hue")


func test_a_biome_with_no_pond_hues_leaves_ponds_deep_water() -> void:
	var biome := Biome.new()
	assert_eq(biome.pond_hue(Vector2i(5, 5)), biome.deep_water)


func test_prop_roles_fill_the_shaders_array() -> void:
	assert_eq(Biome.PropRole.size(), Biome.PROP_ROLE_COUNT)
	var biome := Biome.new()
	biome.blooms = [Color.YELLOW] as Array[Color]
	var colors: PackedColorArray = biome.prop_role_colors()
	assert_eq(colors.size(), Biome.PROP_ROLE_COUNT)
	assert_eq(colors[Biome.PropRole.STONE], biome.stone)
	assert_eq(colors[Biome.PropRole.BLOOM_C], Color.YELLOW, "too few blooms repeat the last")


func test_no_blooms_fall_back_to_foliage() -> void:
	var biome := Biome.new()
	assert_eq(biome.prop_role_colors()[Biome.PropRole.BLOOM_A], biome.foliage)


func test_every_doodad_vertex_names_a_valid_role() -> void:
	for kind: DoodadLibrary.Kind in DoodadLibrary.all_kinds():
		var arrays: Array = DoodadLibrary.mesh_of(kind).surface_get_arrays(0)
		assert_null(arrays[Mesh.ARRAY_COLOR], "a doodad mesh bakes no colour")
		var roles: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
		assert_gt(roles.size(), 0)
		for role: Vector2 in roles:
			assert_between(int(role.x), 0, Biome.PROP_ROLE_COUNT - 1)
			assert_gt(role.y, 0.0, "a shade multiplies the role's colour")


func test_push_biome_colours_the_terrain_material() -> void:
	var material := ShaderMaterial.new()
	material.shader = load("res://scripts/rendering/shaders/terrain_surface.gdshader") as Shader
	var biome := _biome()
	biome.rock_light = Color(0.7, 0.1, 0.1)
	TerrainShading.push_biome(material, biome, _catalog(["Dirt"] as Array[String]))
	assert_eq(material.get_shader_parameter("rock_light"), Color(0.7, 0.1, 0.1))
	var tiles: PackedColorArray = material.get_shader_parameter("tile_colors")
	assert_eq(tiles[0], Color(0.1, 0.2, 0.3))


func test_dress_lighting_tints_the_rigs_suns() -> void:
	var rig: Node = (load(Scenario.DEFAULT_LIGHTING_SCENE) as PackedScene).instantiate()
	var biome := Biome.new()
	biome.key_light_color = Color(1, 0.5, 0.25)
	biome.fill_light_energy = 0.05
	biome.dress_lighting(rig)
	assert_eq((rig.get_node("KeySun") as DirectionalLight3D).light_color, Color(1, 0.5, 0.25))
	assert_almost_eq((rig.get_node("FillSun") as DirectionalLight3D).light_energy, 0.05, 1e-6)
	rig.free()


func test_the_biome_environment_is_a_copy() -> void:
	var base := Environment.new()
	base.ambient_light_energy = 0.3
	var biome := Biome.new()
	biome.ambient_energy = 0.9
	var env: Environment = biome.environment_from(base)
	assert_ne(env, base)
	assert_almost_eq(env.ambient_light_energy, 0.9, 1e-6)
	assert_almost_eq(base.ambient_light_energy, 0.3, 1e-6, "the project default is untouched")


func test_an_unlit_scenario_gets_the_biome_environment() -> void:
	var scenario := Scenario.new()
	scenario._ensure_lighting()
	assert_eq(scenario.find_children("*", "WorldEnvironment", true, false).size(), 1)
	scenario.free()


func test_a_scenario_with_its_own_environment_keeps_it() -> void:
	var scenario := Scenario.new()
	var own := WorldEnvironment.new()
	scenario.add_child(own)
	scenario._ensure_lighting()
	assert_eq(scenario.find_children("*", "WorldEnvironment", true, false), [own])
	scenario.free()
