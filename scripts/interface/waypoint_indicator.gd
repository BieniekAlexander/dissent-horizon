class_name WaypointIndicator
extends Node3D

#region Constants
const Y_OFFSET    := 0.2
const MARKER_SIZE := 0.5
const COLOR       := Color(1.0, 0.85, 0.1)  # gold
#endregion

#region Properties
var _mesh: ImmediateMesh
var _mesh_instance: MeshInstance3D
var _from_world: Vector3
#endregion

#region Lifecycle
func _ready() -> void:
	_mesh = ImmediateMesh.new()
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = _mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = true
	_mesh_instance.material_override = mat
	_mesh_instance.get_active_material(0).render_priority = RenderPriority.WAYPOINT_PRIORITY
	add_child(_mesh_instance)
#endregion

#region Public API
## Position the indicator at `destination` and draw a line from `from_pos`.
func configure(destination: Vector3, from_pos: Vector3) -> void:
	global_position = destination
	_from_world = from_pos
	_redraw()
#endregion

#region Private helpers
func _redraw() -> void:
	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	_mesh.surface_set_color(COLOR)

	var dest_local  := Vector3(0.0, Y_OFFSET, 0.0)
	var from_local  := to_local(_from_world) + Vector3(0.0, Y_OFFSET, 0.0)

	# Line from predecessor position to this waypoint
	_mesh.surface_add_vertex(from_local)
	_mesh.surface_add_vertex(dest_local)

	# Diamond marker at destination
	var r := MARKER_SIZE
	_mesh.surface_add_vertex(dest_local + Vector3(-r, 0.0,  0.0))
	_mesh.surface_add_vertex(dest_local + Vector3( 0.0, 0.0,  r))
	_mesh.surface_add_vertex(dest_local + Vector3( 0.0, 0.0,  r))
	_mesh.surface_add_vertex(dest_local + Vector3( r, 0.0,  0.0))
	_mesh.surface_add_vertex(dest_local + Vector3( r, 0.0,  0.0))
	_mesh.surface_add_vertex(dest_local + Vector3( 0.0, 0.0, -r))
	_mesh.surface_add_vertex(dest_local + Vector3( 0.0, 0.0, -r))
	_mesh.surface_add_vertex(dest_local + Vector3(-r, 0.0,  0.0))

	_mesh.surface_end()
#endregion
