extends GutTest

## Tests for the mesh -> heightfield PIPELINE on the two shapes the reference scenarios use:
## a domed disc island, and a square with a vertical-sided cylindrical plateau.
##
## The geometry is BUILT HERE rather than loaded from resources/terrain/*.tres, and that is
## deliberate. Those files are live maps: the Map's Create Terrain Mesh button and the terrain
## brush both write to them, so an earlier version of this test — which asserted the shipped
## plateau still had a 6-unit cap and a steep ring at radius 18 — started failing the moment
## the map was authored on. A test must not pin content someone edits. What is worth pinning is
## that the pipeline turns these SHAPES into the right field, which is what this does.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_MeshTerrainScenarios.gd

const CATALOG_PATH := "res://resources/terrain/tile_catalog.tres"

# Small enough to bake fast, large enough for the features to span many cells.
const PLAY := Vector2i(39, 39)  # -> an 80x80 corner grid
const DISC_RADIUS: float = 25.0
const DISC_HEIGHT: float = 2.0
const PLATEAU_RADIUS: float = 10.0
const PLATEAU_HEIGHT: float = 4.0
const SQUARE_HALF: float = 60.0


func _terrain() -> TerrainData:
	var data := TerrainData.new()
	data.play_size = PLAY
	data.catalog = load(CATALOG_PATH)
	return data


func _mesh(a_verts: PackedVector3Array) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = a_verts
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return am


## h(r) = H * (1 - (r/R)^2), as a fan of concentric rings. Nothing beyond the rim.
func _disc_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var rings: int = 24
	var segs: int = 48
	for ring: int in rings:
		var r0: float = DISC_RADIUS * float(ring) / rings
		var r1: float = DISC_RADIUS * float(ring + 1) / rings
		for seg: int in segs:
			var a0: float = TAU * float(seg) / segs
			var a1: float = TAU * float(seg + 1) / segs
			var p00: Vector3 = _dome(r0, a0)
			var p01: Vector3 = _dome(r0, a1)
			var p10: Vector3 = _dome(r1, a0)
			var p11: Vector3 = _dome(r1, a1)
			if ring == 0:
				verts.append_array([p10, p11, p00])
			else:
				verts.append_array([p00, p10, p11, p00, p11, p01])
	return _mesh(verts)


func _dome(a_r: float, a_angle: float) -> Vector3:
	var t: float = a_r / DISC_RADIUS
	return Vector3(a_r * cos(a_angle), DISC_HEIGHT * (1.0 - t * t), a_r * sin(a_angle))


## A flat square with a vertical-sided cylinder standing on it. The square passes UNDER the
## cylinder — the baker keeps the highest surface, so a plateau can be a solid on the ground
## rather than a stitched sheet.
func _plateau_mesh() -> ArrayMesh:
	var s: float = SQUARE_HALF
	var verts := PackedVector3Array(
		[
			Vector3(-s, 0, -s),
			Vector3(s, 0, -s),
			Vector3(s, 0, s),
			Vector3(-s, 0, -s),
			Vector3(s, 0, s),
			Vector3(-s, 0, s),
		]
	)
	var segs: int = 48
	for seg: int in segs:
		var a0: float = TAU * float(seg) / segs
		var a1: float = TAU * float(seg + 1) / segs
		var r0 := Vector3(PLATEAU_RADIUS * cos(a0), PLATEAU_HEIGHT, PLATEAU_RADIUS * sin(a0))
		var r1 := Vector3(PLATEAU_RADIUS * cos(a1), PLATEAU_HEIGHT, PLATEAU_RADIUS * sin(a1))
		verts.append_array([Vector3(0, PLATEAU_HEIGHT, 0), r0, r1])
		var g0 := Vector3(r0.x, 0.0, r0.z)
		var g1 := Vector3(r1.x, 0.0, r1.z)
		verts.append_array([r0, g0, g1, r0, g1, r1])  # vertical walls
	return _mesh(verts)


func _cell_center(a_data: TerrainData, a_cell: Vector2i) -> Vector2:
	var half_w: float = (a_data.dimensions.x - 1) * 0.5
	var half_d: float = (a_data.dimensions.y - 1) * 0.5
	return Vector2(a_cell.x + 0.5 - half_w, a_cell.y + 0.5 - half_d)


func _center_corner(a_data: TerrainData) -> int:
	return int((a_data.dimensions.x - 1) * 0.5)


func _corner(a_data: TerrainData, a_cx: int, a_cz: int) -> float:
	return a_data.heights[a_cz * a_data.dimensions.x + a_cx]


# --- disc -------------------------------------------------------------------


func test_disc_apex_and_rim_heights():
	var data := _terrain()
	data.bake_source_mesh(_disc_mesh())
	var c: int = _center_corner(data)
	assert_almost_eq(_corner(data, c, c), DISC_HEIGHT, 0.02, "dome apex")
	assert_lt(_corner(data, c + int(DISC_RADIUS) - 1, c), 0.25, "rim is near ground level")


func test_disc_is_a_disc():
	var data := _terrain()
	data.bake_source_mesh(_disc_mesh())
	var inside: int = 0
	var outside: int = 0
	for z: int in data.grid_depth():
		for x: int in data.grid_width():
			var cell := Vector2i(x, z)
			var r: float = _cell_center(data, cell).length()
			var surfaced: bool = not data.is_cell_void(cell)
			# Skip the one-cell band either side of the rim, where a curved boundary on a grid
			# is legitimately ambiguous.
			if r < DISC_RADIUS - 1.5 and surfaced:
				inside += 1
			elif r > DISC_RADIUS + 1.5 and surfaced:
				outside += 1
	assert_eq(outside, 0, "nothing is surfaced beyond the rim")
	var expected: float = PI * pow(DISC_RADIUS - 1.5, 2.0)
	assert_almost_eq(float(inside), expected, expected * 0.03, "the interior is surfaced")


func test_disc_has_no_steep_cells():
	var data := _terrain()
	data.bake_source_mesh(_disc_mesh())
	for z: int in data.grid_depth():
		for x: int in data.grid_width():
			var cell := Vector2i(x, z)
			if data.is_cell_void(cell):
				continue
			assert_lte(
				data.cell_height_spread(cell),
				TerrainGrid.MAX_SLOPE_DIFF,
				"a shallow dome is walkable at cell (%d, %d)" % [x, z]
			)


## The bake owns the void layer and nothing else: a material painted before a re-bake survives
## it, void or not, and a void cell is out of play.
func test_bake_writes_voids_and_leaves_materials_alone():
	var data := _terrain()
	var types := PackedByteArray()
	types.resize(data.grid_width() * data.grid_depth())
	types.fill(1)
	data.tile_types = types
	data.bake_source_mesh(_disc_mesh())
	assert_eq(data.tile_types, types, "materials are untouched")
	var corner := Vector2i(0, 0)
	assert_true(data.is_cell_void(corner), "the grid corner is far off the disc")
	assert_false(data.is_cell_in_play(corner))


# --- plateau ----------------------------------------------------------------


func test_plateau_surface_covers_the_whole_grid():
	var data := _terrain()
	data.bake_source_mesh(_plateau_mesh())
	for z: int in data.grid_depth():
		for x: int in data.grid_width():
			assert_false(
				data.is_cell_void(Vector2i(x, z)),
				"a full square leaves cell (%d, %d) on the surface" % [x, z]
			)


func test_plateau_cap_and_ground_heights():
	var data := _terrain()
	data.bake_source_mesh(_plateau_mesh())
	var c: int = _center_corner(data)
	assert_almost_eq(_corner(data, c, c), PLATEAU_HEIGHT, 0.001, "cap")
	assert_almost_eq(_corner(data, c + 25, c), 0.0, 0.001, "ground beside the plateau")
	assert_almost_eq(_corner(data, c, c + 25), 0.0, 0.001)


## The cliff: steep cells ring the cylinder and appear nowhere else — the cap and the ground
## are both dead flat. This is what makes the wall impassable and the top an island.
func test_plateau_rim_is_the_only_steep_ground():
	var data := _terrain()
	data.bake_source_mesh(_plateau_mesh())
	var lo: float = INF
	var hi: float = -INF
	var count: int = 0
	for z: int in data.grid_depth():
		for x: int in data.grid_width():
			var cell := Vector2i(x, z)
			if data.cell_height_spread(cell) <= TerrainGrid.MAX_SLOPE_DIFF:
				continue
			count += 1
			var r: float = _cell_center(data, cell).length()
			lo = minf(lo, r)
			hi = maxf(hi, r)
	assert_gt(count, 0, "the cylinder wall produces steep cells")
	assert_almost_eq(lo, PLATEAU_RADIUS, 1.5, "steep cells start at the cylinder radius")
	assert_almost_eq(hi, PLATEAU_RADIUS, 1.5, "steep cells end at the cylinder radius")


func test_plateau_cap_is_flat_and_the_ground_is_flat():
	var data := _terrain()
	data.bake_source_mesh(_plateau_mesh())
	var c: int = _center_corner(data)
	var center := Vector2i(c, c)
	assert_true(data.cell_is_flat(center), "cap is level")
	assert_true(data.cell_is_flat(center + Vector2i(25, 0)), "ground is level")
	assert_true(
		data.cell_supports_entity(center + Vector2i(25, 0)),
		"ground beside the plateau takes structures"
	)


func test_plateau_rim_cells_do_not_support_entities():
	var data := _terrain()
	data.bake_source_mesh(_plateau_mesh())
	var checked: int = 0
	for z: int in data.grid_depth():
		for x: int in data.grid_width():
			var cell := Vector2i(x, z)
			if data.cell_height_spread(cell) <= TerrainGrid.MAX_SLOPE_DIFF:
				continue
			checked += 1
			assert_false(
				data.cell_supports_entity(cell), "steep rim cell (%d, %d) is unstandable" % [x, z]
			)
	assert_gt(checked, 0)
