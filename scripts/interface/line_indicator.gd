class_name LineIndicator
extends Node3D

## The preview of a move-line order while the button is held: the dragged line itself, and a small
## diamond where each actor will stand. Redrawn whole every frame from what the controller hands
## it, the way RallyIndicator is, and for the same reason — it follows a live query, not a pooled
## order. See gdd/systems/commands/move-line-drag.md.

const Y_OFFSET: float = 0.2
const MARKER_SIZE: float = 0.3
## Green: an order about to be given, where the waypoint indicators' gold is one already given.
const COLOR: Color = Color(0.45, 0.95, 0.45)

var _mesh: ImmediateMesh
var _mesh_instance: MeshInstance3D


func _ready() -> void:
	_mesh = ImmediateMesh.new()
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = _mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = true
	mat.render_priority = RenderPriority.WAYPOINT_PRIORITY
	_mesh_instance.material_override = mat
	add_child(_mesh_instance)


## Draw the line from `a_start` to `a_end` and a marker at each of `a_points` (world positions).
func show_line(a_start: Vector3, a_end: Vector3, a_points: Array[Vector3]) -> void:
	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	_mesh.surface_set_color(COLOR)
	_mesh.surface_add_vertex(to_local(a_start + Vector3(0.0, Y_OFFSET, 0.0)))
	_mesh.surface_add_vertex(to_local(a_end + Vector3(0.0, Y_OFFSET, 0.0)))
	for point: Vector3 in a_points:
		_add_marker(point + Vector3(0.0, Y_OFFSET, 0.0))
	_mesh.surface_end()


func clear_line() -> void:
	if _mesh != null:
		_mesh.clear_surfaces()


func _add_marker(a_point_world: Vector3) -> void:
	var p: Vector3 = to_local(a_point_world)
	var r: float = MARKER_SIZE
	var corners: Array[Vector3] = [
		p + Vector3(-r, 0.0, 0.0),
		p + Vector3(0.0, 0.0, r),
		p + Vector3(r, 0.0, 0.0),
		p + Vector3(0.0, 0.0, -r),
	]
	for i: int in 4:
		_mesh.surface_add_vertex(corners[i])
		_mesh.surface_add_vertex(corners[(i + 1) % 4])
