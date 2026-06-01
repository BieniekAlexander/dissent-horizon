class_name CommandLineIndicator
extends Node3D

## Draws a line from the unit's current position to its nearest command target.
## Visible only while the parent unit is selected.

const Y_OFFSET := 0.15
const COLOR    := Color(0.4, 0.8, 1.0)  # light blue

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
	_mesh_instance.material_override = mat
	add_child(_mesh_instance)

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_redraw()

func _redraw() -> void:
	_mesh.clear_surfaces()

	var unit := get_parent() as Commandable
	if unit == null or not unit.selectable.is_selected():
		return

	var cmd := unit.current_command()
	if cmd == null or not cmd.requires_position():
		return

	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	_mesh.surface_set_color(COLOR)
	_mesh.surface_add_vertex(Vector3(0.0, Y_OFFSET, 0.0))
	_mesh.surface_add_vertex(to_local(cmd.message.position) + Vector3(0.0, Y_OFFSET, 0.0))
	_mesh.surface_end()
