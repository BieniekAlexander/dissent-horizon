extends GutTest

## Tests for MeshHeightfieldBaker — deriving a TerrainData heightfield from a triangle mesh.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_MeshHeightfieldBaker.gd


## Build an ArrayMesh from a flat list of triangle vertices (3 per triangle, unindexed).
func _mesh_from_tris(a_tris: PackedVector3Array) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = a_tris
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return am


## A flat quad spanning local [-half, half] on both axes at height y.
func _quad(a_half: float, a_y: float) -> PackedVector3Array:
	var a := Vector3(-a_half, a_y, -a_half)
	var b := Vector3(a_half, a_y, -a_half)
	var c := Vector3(a_half, a_y, a_half)
	var d := Vector3(-a_half, a_y, a_half)
	return PackedVector3Array([a, b, c, a, c, d])


func _height_at(a_res, a_dims: Vector2i, a_cx: int, a_cz: int) -> float:
	return a_res.heights[a_cz * a_dims.x + a_cx]


func _hit_at(a_res, a_dims: Vector2i, a_cx: int, a_cz: int) -> int:
	return a_res.hit[a_cz * a_dims.x + a_cx]


func test_flat_quad_covers_every_corner_at_one_height():
	var dims := Vector2i(9, 9)
	var res = MeshHeightfieldBaker.bake(_mesh_from_tris(_quad(10.0, 2.5)), dims)
	assert_true(res.is_fully_covered(), "a quad larger than the grid covers every corner")
	assert_eq(res.hit_count(), 81)
	for i: int in res.heights.size():
		assert_almost_eq(res.heights[i], 2.5, 0.0001)


func test_tilted_plane_interpolates_linearly():
	# Height ramps with x: y = x, over a quad spanning well past the grid.
	var h: float = 10.0
	var tris := PackedVector3Array([
		Vector3(-h, -h, -h), Vector3(h, h, -h), Vector3(h, h, h),
		Vector3(-h, -h, -h), Vector3(h, h, h), Vector3(-h, -h, h),
	])
	var dims := Vector2i(9, 9)
	var res = MeshHeightfieldBaker.bake(_mesh_from_tris(tris), dims)
	assert_true(res.is_fully_covered())
	# Corner (cx, cz) sits at local x = cx - 4, so its height should be cx - 4.
	for cz: int in 9:
		for cx: int in 9:
			assert_almost_eq(_height_at(res, dims, cx, cz), float(cx) - 4.0, 0.0001,
				"corner (%d, %d)" % [cx, cz])


func test_uncovered_corners_are_reported_as_missing():
	# A quad covering only the middle of a 9x9 grid (local [-1, 1]).
	var dims := Vector2i(9, 9)
	var res = MeshHeightfieldBaker.bake(_mesh_from_tris(_quad(1.0, 3.0)), dims)
	assert_false(res.is_fully_covered(), "a small quad leaves the rim uncovered")
	# Centre corner (4,4) is local (0,0) — inside the quad.
	assert_eq(_hit_at(res, dims, 4, 4), 1, "centre corner is covered")
	assert_almost_eq(_height_at(res, dims, 4, 4), 3.0, 0.0001)
	# Corner (0,0) is local (-4,-4) — well outside.
	assert_eq(_hit_at(res, dims, 0, 0), 0, "rim corner is not covered")


func test_uncovered_corners_inherit_the_nearest_covered_height():
	# Same small quad, raised — the fill should extend 3.0 outward rather than leave 0.0,
	# so the derived collider has no cliff at the surface's rim.
	var dims := Vector2i(9, 9)
	var res = MeshHeightfieldBaker.bake(_mesh_from_tris(_quad(1.0, 3.0)), dims)
	for i: int in res.heights.size():
		assert_almost_eq(res.heights[i], 3.0, 0.0001, "corner %d filled outward" % i)


func test_grid_with_no_coverage_stays_flat():
	var dims := Vector2i(5, 5)
	# A quad far off to the side of the grid.
	var res = MeshHeightfieldBaker.bake(
		_mesh_from_tris(_quad(1.0, 7.0)), dims, Transform3D(Basis(), Vector3(500, 0, 500)))
	assert_eq(res.hit_count(), 0, "nothing covered")
	for i: int in res.heights.size():
		assert_almost_eq(res.heights[i], 0.0, 0.0001, "stays flat rather than erroring")


## The property a vertical-walled plateau depends on: a wall projects to zero XZ area, so it
## is never the surface and must not contribute a height.
func test_vertical_triangles_are_skipped():
	var wall := PackedVector3Array([
		Vector3(0, 0, 0), Vector3(0, 5, 0), Vector3(0, 5, 2),
	])
	var dims := Vector2i(5, 5)
	var res = MeshHeightfieldBaker.bake(_mesh_from_tris(wall), dims)
	assert_eq(res.triangle_count, 1)
	assert_eq(res.skipped_triangles, 1, "the vertical wall contributes nothing")
	assert_eq(res.hit_count(), 0)


## A modelled plateau is a solid: a cap above a floor. The playable surface is the top.
func test_highest_surface_wins_over_a_lower_one():
	var tris := _quad(10.0, 0.0)
	tris.append_array(_quad(2.0, 4.0))   # a raised cap over the middle
	var dims := Vector2i(9, 9)
	var res = MeshHeightfieldBaker.bake(_mesh_from_tris(tris), dims)
	assert_true(res.is_fully_covered())
	assert_almost_eq(_height_at(res, dims, 4, 4), 4.0, 0.0001, "centre takes the cap")
	assert_almost_eq(_height_at(res, dims, 0, 0), 0.0, 0.0001, "rim takes the floor")


## Order must not matter — the cap is found whether it is rasterized before or after the floor.
func test_highest_surface_wins_regardless_of_triangle_order():
	var tris := _quad(2.0, 4.0)
	tris.append_array(_quad(10.0, 0.0))
	var dims := Vector2i(9, 9)
	var res = MeshHeightfieldBaker.bake(_mesh_from_tris(tris), dims)
	assert_almost_eq(_height_at(res, dims, 4, 4), 4.0, 0.0001)


func test_indexed_and_unindexed_meshes_agree():
	var dims := Vector2i(9, 9)
	var flat := _quad(10.0, 1.5)
	var unindexed = MeshHeightfieldBaker.bake(_mesh_from_tris(flat), dims)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([flat[0], flat[1], flat[2], flat[5]])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var indexed = MeshHeightfieldBaker.bake(am, dims)

	assert_eq(indexed.hit_count(), unindexed.hit_count())
	for i: int in indexed.heights.size():
		assert_almost_eq(indexed.heights[i], unindexed.heights[i], 0.0001, "corner %d" % i)


func test_mesh_transform_is_applied():
	var dims := Vector2i(9, 9)
	var lifted := Transform3D(Basis(), Vector3(0, 6.0, 0))
	var res = MeshHeightfieldBaker.bake(_mesh_from_tris(_quad(10.0, 1.0)), dims, lifted)
	assert_almost_eq(_height_at(res, dims, 4, 4), 7.0, 0.0001)


func test_null_mesh_yields_a_flat_full_size_field():
	var dims := Vector2i(6, 7)
	var res = MeshHeightfieldBaker.bake(null, dims)
	assert_eq(res.heights.size(), 42)
	assert_eq(res.hit_count(), 0)
