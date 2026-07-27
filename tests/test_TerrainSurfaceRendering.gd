extends GutTest

## Tests for drawing the AUTHORED SURFACE MESH as the terrain: the per-cell lookup data the
## shader needs, and the seam that lets Fog find the terrain material whichever node draws it.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_TerrainSurfaceRendering.gd

const CATALOG_PATH := "res://resources/terrain/tile_catalog.tres"


class StubMap extends Map:
	func _ready() -> void:
		pass


func _make_terrain(a_play: Vector2i) -> TerrainData:
	var data := TerrainData.new()
	data.play_size = a_play
	data.catalog = load(CATALOG_PATH)
	return data


## A throwaway surface for TerrainSurface to draw — the geometry is irrelevant to what these
## tests assert, it just refuses to draw nothing.
func _trivial_mesh() -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(1, 0, 1)])
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return am


func _make_map() -> StubMap:
	var stub := StubMap.new()
	var region := NavigationRegion3D.new()
	region.name = "NavigationRegion"
	var body := StaticBody3D.new()
	body.name = "Body"
	# Map resolves $NavigationRegion/Body/Shape in an @onready, which errors on a stub that
	# lacks it — @onready assignments still run when _ready is overridden.
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	body.add_child(shape)
	region.add_child(body)
	stub.add_child(region)
	return stub


# --- cell data texture ------------------------------------------------------

func test_cell_data_texture_is_one_texel_per_cell():
	var data := _make_terrain(Vector2i(4, 4))
	var tex: ImageTexture = data.cell_data_texture()
	assert_eq(tex.get_width(), data.grid_width())
	assert_eq(tex.get_height(), data.grid_depth())


func test_cell_data_texture_carries_the_tile_index():
	var data := _make_terrain(Vector2i(4, 4))
	var gw: int = data.grid_width()
	var gd: int = data.grid_depth()
	data.tile_types = PackedByteArray()
	data.tile_types.resize(gw * gd)
	data.tile_types[2 * gw + 3] = 1   # a non-default material

	var image: Image = data.cell_data_texture().get_image()
	assert_eq(roundi(image.get_pixel(3, 2).r * 255.0), 1, "the painted cell carries index 1")
	assert_eq(roundi(image.get_pixel(1, 1).r * 255.0), 0, "untouched cell is the open default")


func test_cell_data_texture_of_an_unpainted_terrain_is_all_default():
	var data := _make_terrain(Vector2i(4, 4))
	var image: Image = data.cell_data_texture().get_image()
	for z: int in data.grid_depth():
		for x: int in data.grid_width():
			assert_eq(roundi(image.get_pixel(x, z).r * 255.0), 0, "cell (%d, %d)" % [x, z])


## The steep channel must be the SAME test the navmesh runs, or the terrain lies about where a
## unit can walk — which is the whole reason cliff shading moved off the interpolated normal.
func test_steep_channel_matches_the_navmesh_slope_test():
	var data := _make_terrain(Vector2i(6, 6))
	var w: int = data.dimensions.x
	var h := PackedFloat32Array()
	h.resize(w * data.dimensions.y)
	# A one-corner spike: every cell touching it exceeds MAX_SLOPE_DIFF, the rest are flat.
	h[3 * w + 3] = TerrainGrid.MAX_SLOPE_DIFF * 4.0
	data.heights = h

	var image: Image = data.cell_data_texture().get_image()
	var disagreements: int = 0
	var flagged: int = 0
	for z: int in data.grid_depth():
		for x: int in data.grid_width():
			var expected: bool = data.cell_height_spread(Vector2i(x, z)) > TerrainGrid.MAX_SLOPE_DIFF
			var got: bool = image.get_pixel(x, z).g > 0.5
			if expected != got:
				disagreements += 1
			if got:
				flagged += 1
	assert_eq(disagreements, 0, "every cell agrees with cell_height_spread")
	assert_eq(flagged, 4, "the four cells around the spike are steep")


func test_flat_terrain_flags_nothing_steep():
	var data := _make_terrain(Vector2i(6, 6))
	var h := PackedFloat32Array()
	h.resize(data.dimensions.x * data.dimensions.y)
	h.fill(3.0)                       # flat, but not at zero
	data.heights = h
	var image: Image = data.cell_data_texture().get_image()
	for z: int in data.grid_depth():
		for x: int in data.grid_width():
			assert_lt(image.get_pixel(x, z).g, 0.5, "cell (%d, %d) is walkable" % [x, z])


## Steepness and tile identity share the texture but must not contaminate each other.
func test_steep_and_tile_channels_are_independent():
	var data := _make_terrain(Vector2i(6, 6))
	var gw: int = data.grid_width()
	var w: int = data.dimensions.x
	var h := PackedFloat32Array()
	h.resize(w * data.dimensions.y)
	h[2 * w + 2] = TerrainGrid.MAX_SLOPE_DIFF * 4.0
	data.heights = h
	data.tile_types = PackedByteArray()
	data.tile_types.resize(gw * data.grid_depth())
	# Cell (0,0), whose corners are (0,0)..(1,1) — clear of the spike at corner (2,2), which
	# makes steep all FOUR cells sharing it.
	data.tile_types[0] = 1            # a non-default material, on flat ground

	var image: Image = data.cell_data_texture().get_image()
	assert_eq(roundi(image.get_pixel(0, 0).r * 255.0), 1, "the material keeps its index")
	assert_lt(image.get_pixel(0, 0).g, 0.5, "and is not marked steep")
	assert_gt(image.get_pixel(2, 2).g, 0.5, "the spike cell is steep")
	assert_eq(roundi(image.get_pixel(2, 2).r * 255.0), 0, "and still reads as open ground")


# --- palette ----------------------------------------------------------------

func test_map_color_array_is_padded_to_the_requested_length():
	var catalog: TerrainTileCatalog = load(CATALOG_PATH)
	var colors: PackedColorArray = catalog.map_color_array(256)
	assert_eq(colors.size(), 256)
	# Real entries come from the catalog...
	assert_eq(colors[0], catalog.map_color(0))
	assert_eq(colors[1], catalog.map_color(1))
	# ...and padding degrades to open ground rather than to black, so an out-of-range index
	# in the cell texture renders as ground instead of as a hole.
	assert_eq(colors[255], TileType.DEFAULT_MAP_COLOR)


func test_texture_flag_array_marks_only_types_with_a_texture():
	var catalog: TerrainTileCatalog = load(CATALOG_PATH)
	var flags: PackedFloat32Array = catalog.texture_flag_array(256)
	assert_eq(flags.size(), 256)
	for i: int in catalog.count():
		var expected: float = 1.0 if catalog.types[i].texture != null else 0.0
		assert_eq(flags[i], expected, "type %d" % i)
	assert_eq(flags[255], 0.0, "padding claims no texture")


# --- the Fog seam -----------------------------------------------------------

func test_terrain_material_resolves_a_terrain_surface():
	var map := _make_map()
	add_child_autofree(map)
	var body: StaticBody3D = map.get_node("NavigationRegion/Body")
	var surface := TerrainSurface.new()
	surface.name = "TerrainSurface"
	surface.terrain_data_override = _make_terrain(Vector2i(4, 4))
	surface.source_mesh_override = _trivial_mesh()
	var material := ShaderMaterial.new()
	surface.material = material
	body.add_child(surface)
	assert_eq(map.terrain_material(), material)


func test_terrain_material_falls_back_to_the_generated_mesh_node():
	var map := _make_map()
	add_child_autofree(map)
	var body: StaticBody3D = map.get_node("NavigationRegion/Body")
	var gen := HeightmapMeshGenerator.new()
	gen.name = "HeightmapMeshGenerator"
	var material := ShaderMaterial.new()
	gen.material = material
	body.add_child(gen)
	assert_eq(map.terrain_material(), material,
		"a brush-authored map still resolves its material")


func test_terrain_material_is_null_when_nothing_draws_the_terrain():
	var map := _make_map()
	add_child_autofree(map)
	assert_null(map.terrain_material())
