extends GutTest

## MeshPrimitives: closed, outward-wound convex solids, and StructureModels.to_mesh turning
## slot triangle lists into tintable surfaces.


## The volume a closed triangle list encloses, by the divergence theorem. Positive when every
## triangle is clockwise seen from outside, Godot's front face.
func _volume(triangles: PackedVector3Array) -> float:
	var total: float = 0.0
	for i: int in range(0, triangles.size(), 3):
		total += triangles[i].dot(triangles[i + 2].cross(triangles[i + 1])) / 6.0
	return total


func _bounds(triangles: PackedVector3Array) -> AABB:
	var out: AABB = AABB(triangles[0], Vector3.ZERO)
	for v: Vector3 in triangles:
		out = out.expand(v)
	return out


func test_a_box_is_closed_and_wound_outward() -> void:
	var box: PackedVector3Array = MeshPrimitives.box(Vector3(-1, 0, -2), Vector3(1, 3, 2))
	assert_almost_eq(_volume(box), 2.0 * 3.0 * 4.0, 0.0001)


func test_a_box_takes_its_corners_in_either_order() -> void:
	var box: PackedVector3Array = MeshPrimitives.box(Vector3(1, 3, 2), Vector3(-1, 0, -2))
	assert_almost_eq(_volume(box), 24.0, 0.0001)


func test_a_pyramid_holds_a_third_of_its_prism() -> void:
	var pyramid: PackedVector3Array = MeshPrimitives.pyramid(Vector2.ZERO, 1.0, 0.0, 3.0)
	assert_almost_eq(_volume(pyramid), 2.0 * 2.0 * 3.0 / 3.0, 0.0001)
	assert_almost_eq(_bounds(pyramid).size, Vector3(2, 3, 2), Vector3.ONE * 0.0001)


func test_a_beam_runs_between_its_ends() -> void:
	var beam: PackedVector3Array = MeshPrimitives.beam(Vector3(0, 0, 0), Vector3(0, 0, 4), 0.5)
	assert_almost_eq(_volume(beam), 0.5 * 0.5 * 4.0, 0.0001)
	assert_almost_eq(_bounds(beam).size.z, 4.0, 0.0001)


func test_a_slanted_beam_keeps_its_volume() -> void:
	var beam: PackedVector3Array = MeshPrimitives.beam(Vector3(0, 0, 0), Vector3(3, 4, 0), 0.2)
	assert_almost_eq(_volume(beam), 0.2 * 0.2 * 5.0, 0.0001)


func test_a_hip_roof_stays_over_its_rectangle_and_peaks_at_its_ridge() -> void:
	var roof: PackedVector3Array = MeshPrimitives.hip_roof(
		Vector3(-2, 1, -1), Vector3(2, 1, 1), 2.0, 0.8
	)
	assert_gt(_volume(roof), 0.0, "closed and wound outward")
	var bounds: AABB = _bounds(roof)
	assert_almost_eq(bounds.position, Vector3(-2, 1, -1), Vector3.ONE * 0.0001)
	assert_almost_eq(bounds.size, Vector3(4, 1, 2), Vector3.ONE * 0.0001)


func test_a_dome_lies_within_its_sphere() -> void:
	var dome: PackedVector3Array = MeshPrimitives.dome(Vector3(0, 1, 0), 2.0, 3, 8)
	assert_gt(_volume(dome), 0.0)
	assert_true(
		Array(dome).all(func(v: Vector3) -> bool: return v.distance_to(Vector3(0, 1, 0)) <= 2.0001)
	)


func test_to_mesh_makes_one_tintable_surface_per_filled_slot() -> void:
	var parts: Dictionary = {
		StructureModels.Slot.BODY: MeshPrimitives.box(Vector3.ZERO, Vector3.ONE),
		StructureModels.Slot.TRIM: PackedVector3Array(),
		StructureModels.Slot.ACCENT: MeshPrimitives.box(Vector3.ONE, Vector3(2, 2, 2)),
	}
	var mesh: ArrayMesh = StructureModels.to_mesh(parts)
	assert_eq(mesh.get_surface_count(), 2)
	for surface: int in range(mesh.get_surface_count()):
		assert_true(mesh.surface_get_material(surface) is BaseMaterial3D, "MeshVisual tints it")


func test_to_mesh_normals_point_out_of_the_solid() -> void:
	var mesh: ArrayMesh = StructureModels.to_mesh(
		{StructureModels.Slot.BODY: MeshPrimitives.box(-Vector3.ONE, Vector3.ONE)}
	)
	var arrays: Array = mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for i: int in range(vertices.size()):
		assert_gt(normals[i].dot(vertices[i]), 0.0)
