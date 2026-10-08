extends GutTest

## The overlay's geometry collector: what each primitive adds, and what a flush writes.

var _pen: BotDebugPen


func before_each() -> void:
	_pen = BotDebugPen.new()


func test_a_quad_is_two_triangles() -> void:
	_pen.quad(Vector3.ZERO, 0.5, Color.WHITE)
	assert_eq(_pen.triangle_vertex_count(), 6)
	assert_eq(_pen.line_vertex_count(), 0)


func test_outlines_are_lines() -> void:
	_pen.square(Vector3.ZERO, 0.5, Color.WHITE)
	assert_eq(_pen.line_vertex_count(), 8, "four edges")
	_pen.ring(Vector3.ZERO, 1.0, Color.WHITE)
	assert_eq(_pen.line_vertex_count(), 8 + 2 * BotDebugPen.RING_SEGMENTS)
	_pen.stick(Vector3.ZERO, 1.0, Color.WHITE)
	_pen.line(Vector3.ZERO, Vector3.ONE, Color.WHITE)
	assert_eq(_pen.line_vertex_count(), 12 + 2 * BotDebugPen.RING_SEGMENTS)
	assert_eq(_pen.triangle_vertex_count(), 0)


func test_an_empty_pen_writes_nothing() -> void:
	var mesh := ImmediateMesh.new()
	assert_true(_pen.is_empty())
	_pen.flush(mesh, Transform3D.IDENTITY)
	assert_eq(mesh.get_surface_count(), 0)


func test_a_flush_writes_one_surface_per_primitive_kind_used() -> void:
	var mesh := ImmediateMesh.new()
	_pen.line(Vector3.ZERO, Vector3.ONE, Color.WHITE)
	_pen.flush(mesh, Transform3D.IDENTITY)
	assert_eq(mesh.get_surface_count(), 1, "lines only")
	mesh.clear_surfaces()
	_pen.quad(Vector3.ZERO, 0.5, Color.WHITE)
	_pen.flush(mesh, Transform3D.IDENTITY)
	assert_eq(mesh.get_surface_count(), 2, "triangles and lines")


func test_marks_are_lifted_and_mapped_into_the_overlay_frame() -> void:
	var mesh := ImmediateMesh.new()
	var offset := Vector3(10.0, 0.0, 0.0)
	_pen.line(offset, offset, Color.WHITE)
	_pen.flush(mesh, Transform3D(Basis.IDENTITY, -offset))
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert_eq(vertices[0], Vector3(0.0, BotDebugPen.Y_LIFT, 0.0))
