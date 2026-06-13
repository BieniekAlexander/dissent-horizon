@tool
class_name EventCommandPoint
extends Node3D

## A follow-up command waypoint for a scenario event. Place these as children of
## an event (e.g. EventSpawnUnits); each one contributes one command to the chain
## issued to the spawned units, in scene-tree order. The command's destination is
## this node's global_position (snapped to the navmesh).

## Which command to issue at this point.
@export_enum("move", "attack_move") var command_type: String = "attack_move"

const _GIZMO_COLOR := Color(1.0, 0.85, 0.2, 0.95)
const _MARKER_SIZE := 0.4

var _gizmo: MeshInstance3D


## Build a fresh Command targeting this point's position. A new CommandMessage and
## Command are created per call so each unit owns its own (commands ref-count the
## message — they must never be shared across units).
func to_command(map: Map) -> Command:
	var nav_map := map.nav_region.get_navigation_map()
	var dest := NavigationServer3D.map_get_closest_point(nav_map, global_position)
	var msg := CommandMessage.new(map, null, null, dest)
	if command_type == "attack_move":
		return AttackMove.new(msg)
	return Command.new(msg)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_refresh_editor_gizmo()


func _refresh_editor_gizmo() -> void:
	if _gizmo == null or not is_instance_valid(_gizmo):
		_gizmo = MeshInstance3D.new()
		_gizmo.mesh = ImmediateMesh.new()
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.vertex_color_use_as_albedo = true
		mat.no_depth_test = true
		_gizmo.material_override = mat
		add_child(_gizmo, false, Node.INTERNAL_MODE_BACK)

	var im := _gizmo.mesh as ImmediateMesh
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	im.surface_set_color(_GIZMO_COLOR)
	# A small 3D cross marker at the local origin.
	var s := _MARKER_SIZE
	im.surface_add_vertex(Vector3(-s, 0, 0)); im.surface_add_vertex(Vector3(s, 0, 0))
	im.surface_add_vertex(Vector3(0, -s, 0)); im.surface_add_vertex(Vector3(0, s, 0))
	im.surface_add_vertex(Vector3(0, 0, -s)); im.surface_add_vertex(Vector3(0, 0, s))
	im.surface_end()
