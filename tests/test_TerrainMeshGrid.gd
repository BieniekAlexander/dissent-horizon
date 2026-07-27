extends GutTest

## Tests for TerrainMeshGrid — the brushable grid surface, and its round-trip through
## MeshHeightfieldBaker.
##
## The property that matters most is the LAST one: at one vertex per gameplay corner, baking
## the drawn surface back into the heightfield must be lossless. If it is not, the terrain the
## player sees and the terrain the game simulates disagree, which is the exact failure the
## single-write-point design (Map.sync_source_mesh_heights) exists to prevent.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_TerrainMeshGrid.gd

const DIMS := Vector2i(12, 9)


func _heights_ramp(a_dims: Vector2i) -> PackedFloat32Array:
	var h := PackedFloat32Array()
	h.resize(a_dims.x * a_dims.y)
	for z: int in a_dims.y:
		for x: int in a_dims.x:
			h[z * a_dims.x + x] = float(x) * 0.25
	return h


func test_create_makes_a_flat_surface_of_the_right_size():
	var mesh: ArrayMesh = TerrainMeshGrid.create(DIMS, 2.5)
	assert_eq(mesh.get_surface_count(), 1)
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert_eq(verts.size(), DIMS.x * DIMS.y, "one vertex per corner")
	for v: Vector3 in verts:
		assert_almost_eq(v.y, 2.5, 0.0001)


func test_vertices_are_shared_and_indexed():
	# Shared vertices are what let a brush move one corner and have every touching triangle
	# follow; per-cell duplicates would need hand-syncing.
	var mesh: ArrayMesh = TerrainMeshGrid.create(DIMS)
	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	assert_eq(verts.size(), DIMS.x * DIMS.y)
	assert_eq(idx.size(), (DIMS.x - 1) * (DIMS.y - 1) * 6, "two triangles per cell")


func test_grid_is_centred_like_the_heightmap_frame():
	# Must match HeightMapShape3D / MeshHeightfieldBaker's centring or the bake lands offset.
	var mesh: ArrayMesh = TerrainMeshGrid.create(DIMS)
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var half_w: float = (DIMS.x - 1) * 0.5
	var half_d: float = (DIMS.y - 1) * 0.5
	assert_almost_eq(verts[0].x, -half_w, 0.0001, "corner (0,0) x")
	assert_almost_eq(verts[0].z, -half_d, 0.0001, "corner (0,0) z")
	var last: Vector3 = verts[DIMS.x * DIMS.y - 1]
	assert_almost_eq(last.x, half_w, 0.0001)
	assert_almost_eq(last.z, half_d, 0.0001)


func test_write_then_read_round_trips():
	var mesh: ArrayMesh = TerrainMeshGrid.create(DIMS)
	var wanted: PackedFloat32Array = _heights_ramp(DIMS)
	TerrainMeshGrid.write_heights(mesh, DIMS, wanted)
	var got: PackedFloat32Array = TerrainMeshGrid.read_heights(mesh, DIMS)
	assert_eq(got.size(), wanted.size())
	for i: int in wanted.size():
		assert_almost_eq(got[i], wanted[i], 0.0001, "corner %d" % i)


func test_flat_surface_has_up_normals():
	var mesh: ArrayMesh = TerrainMeshGrid.create(DIMS, 1.0)
	for n: Vector3 in mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]:
		assert_almost_eq(n.y, 1.0, 0.0001)


## A ramp rising in +x must tilt its normals toward -x. This is what makes brushed slopes shade
## smoothly instead of faceting per cell.
func test_ramp_normals_tilt_against_the_slope():
	var mesh: ArrayMesh = TerrainMeshGrid.create(DIMS)
	TerrainMeshGrid.write_heights(mesh, DIMS, _heights_ramp(DIMS))
	var normals: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
	# An interior corner, away from the clamped rim.
	var n: Vector3 = normals[4 * DIMS.x + 5]
	assert_lt(n.x, -0.1, "normal leans away from the rising side")
	assert_almost_eq(n.z, 0.0, 0.0001, "no slope across z")
	assert_gt(n.y, 0.0)


func test_is_grid_mesh_rejects_the_wrong_size():
	var mesh: ArrayMesh = TerrainMeshGrid.create(DIMS)
	assert_true(TerrainMeshGrid.is_grid_mesh(mesh, DIMS))
	assert_false(TerrainMeshGrid.is_grid_mesh(mesh, Vector2i(8, 8)),
		"a mesh of another size is drawn and baked, but never brushed")
	assert_false(TerrainMeshGrid.is_grid_mesh(null, DIMS))


## The integration property: at one vertex per corner, the surface bakes back to exactly the
## heights it was built from.
func test_baking_the_surface_reproduces_its_heights():
	var mesh: ArrayMesh = TerrainMeshGrid.create(DIMS)
	var wanted: PackedFloat32Array = _heights_ramp(DIMS)
	TerrainMeshGrid.write_heights(mesh, DIMS, wanted)

	var result = MeshHeightfieldBaker.bake(mesh, DIMS)
	assert_true(result.is_fully_covered(), "a full grid covers every corner")
	for i: int in wanted.size():
		assert_almost_eq(result.heights[i], wanted[i], 0.001, "corner %d survives the bake" % i)
