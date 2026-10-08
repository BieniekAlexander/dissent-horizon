class_name BotDebugPen
extends RefCounted

## The geometry one frame of the bot debug overlay draws, collected in world space and written
## to an ImmediateMesh in two surfaces — translucent triangles, then lines — so a layer can mix
## primitives freely without opening a surface per shape.

## Lift every mark slightly off the terrain so it does not z-fight the ground.
const Y_LIFT: float = 0.1
## Segments in a drawn ring: enough to read as round at the iso camera's zoom.
const RING_SEGMENTS: int = 16

var _triangles: PackedVector3Array = PackedVector3Array()
var _triangle_colors: PackedColorArray = PackedColorArray()
var _lines: PackedVector3Array = PackedVector3Array()
var _line_colors: PackedColorArray = PackedColorArray()


## A flat square of half-size `a_half` centred on `a_world_pos`.
func quad(a_world_pos: Vector3, a_half: float, a_color: Color) -> void:
	var c: Vector3 = _lifted(a_world_pos)
	var a: Vector3 = c + Vector3(-a_half, 0.0, -a_half)
	var b: Vector3 = c + Vector3(a_half, 0.0, -a_half)
	var d: Vector3 = c + Vector3(a_half, 0.0, a_half)
	var e: Vector3 = c + Vector3(-a_half, 0.0, a_half)
	for v: Vector3 in [a, b, d, a, d, e]:
		_triangles.append(v)
		_triangle_colors.append(a_color)


## The outline of a flat square of half-size `a_half` centred on `a_world_pos`.
func square(a_world_pos: Vector3, a_half: float, a_color: Color) -> void:
	var c: Vector3 = _lifted(a_world_pos)
	var corners: Array[Vector3] = [
		c + Vector3(-a_half, 0.0, -a_half),
		c + Vector3(a_half, 0.0, -a_half),
		c + Vector3(a_half, 0.0, a_half),
		c + Vector3(-a_half, 0.0, a_half),
	]
	for i: int in corners.size():
		_segment(corners[i], corners[(i + 1) % corners.size()], a_color)


## A flat circle of radius `a_radius` around `a_world_pos`.
func ring(a_world_pos: Vector3, a_radius: float, a_color: Color) -> void:
	var c: Vector3 = _lifted(a_world_pos)
	for i: int in RING_SEGMENTS:
		var from: float = TAU * i / RING_SEGMENTS
		var to: float = TAU * (i + 1) / RING_SEGMENTS
		_segment(
			c + Vector3(cos(from), 0.0, sin(from)) * a_radius,
			c + Vector3(cos(to), 0.0, sin(to)) * a_radius,
			a_color
		)


## A flat X of half-size `a_half` centred on `a_world_pos`: a place written off or given up.
func cross(a_world_pos: Vector3, a_half: float, a_color: Color) -> void:
	var c: Vector3 = _lifted(a_world_pos)
	_segment(c + Vector3(-a_half, 0.0, -a_half), c + Vector3(a_half, 0.0, a_half), a_color)
	_segment(c + Vector3(-a_half, 0.0, a_half), c + Vector3(a_half, 0.0, -a_half), a_color)


## A vertical line of `a_height` rising from `a_world_pos`, so a mark reads from the iso camera.
func stick(a_world_pos: Vector3, a_height: float, a_color: Color) -> void:
	var base: Vector3 = _lifted(a_world_pos)
	_segment(base, base + Vector3(0.0, a_height, 0.0), a_color)


## A straight line between two world positions, each lifted off the ground.
func line(a_from: Vector3, a_to: Vector3, a_color: Color) -> void:
	_segment(_lifted(a_from), _lifted(a_to), a_color)


func is_empty() -> bool:
	return _triangles.is_empty() and _lines.is_empty()


func triangle_vertex_count() -> int:
	return _triangles.size()


func line_vertex_count() -> int:
	return _lines.size()


## Write everything collected into `a_mesh`, mapping world space through `a_to_local`.
func flush(a_mesh: ImmediateMesh, a_to_local: Transform3D) -> void:
	_emit(a_mesh, Mesh.PRIMITIVE_TRIANGLES, _triangles, _triangle_colors, a_to_local)
	_emit(a_mesh, Mesh.PRIMITIVE_LINES, _lines, _line_colors, a_to_local)


static func _emit(
	mesh: ImmediateMesh,
	primitive: Mesh.PrimitiveType,
	vertices: PackedVector3Array,
	colors: PackedColorArray,
	to_local: Transform3D
) -> void:
	if vertices.is_empty():
		return
	mesh.surface_begin(primitive)
	for i: int in vertices.size():
		mesh.surface_set_color(colors[i])
		mesh.surface_add_vertex(to_local * vertices[i])
	mesh.surface_end()


func _segment(a_from: Vector3, a_to: Vector3, a_color: Color) -> void:
	_lines.append(a_from)
	_lines.append(a_to)
	_line_colors.append(a_color)
	_line_colors.append(a_color)


static func _lifted(world_pos: Vector3) -> Vector3:
	return world_pos + Vector3(0.0, Y_LIFT, 0.0)
