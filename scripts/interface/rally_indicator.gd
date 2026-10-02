class_name RallyIndicator
extends Node3D

## Draws the rally-point sequence of every selected rally-capable structure: a line from
## the structure itself to its first waypoint, then on through each subsequent one, with a
## small diamond marker at each stop — same visual language as WaypointIndicator, whose
## per-order pooling this deliberately does NOT reuse.
##
## A rally chain is read fresh off Commandable.rally_commands / Production.job_commands
## every frame (see RTSController._update_rally_indicator) rather than pooled per live
## CommandMessage: those are TEMPLATES that outlive any single order, of variable length,
## and keyed to the current SELECTION rather than to a ref-counted MoveCommand. That is
## exactly ScenarioHighlight's shape (a set that can grow/shrink under a live query), so
## this follows its single-ImmediateMesh, redraw-the-lot-every-frame recipe instead.

const Y_OFFSET: float = 0.2
const MARKER_SIZE: float = 0.4
## Cyan — distinct from WaypointIndicator's gold, so a structure's rally line is never
## mistaken for a unit's active move order when both happen to be on screen together.
const COLOR: Color = Color(0.3, 0.9, 0.95)

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


## Redraws every chain. `chains` is an Array of Array[Vector3] polylines, each expected to
## start with its structure's own position (see the Garrison-occupancy rally task's Q2:
## the structure anchors the sequence, so a single-waypoint rally still draws one line
## rather than nothing). A chain with fewer than two points draws nothing.
func update_chains(a_chains: Array) -> void:
	_mesh.clear_surfaces()
	var has_segment: bool = false
	for chain: Array in a_chains:
		if chain.size() >= 2:
			has_segment = true
			break
	if not has_segment:
		return

	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	_mesh.surface_set_color(COLOR)
	for chain: Array in a_chains:
		for i in range(chain.size() - 1):
			var a: Vector3 = (chain[i] as Vector3) + Vector3(0.0, Y_OFFSET, 0.0)
			var b: Vector3 = (chain[i + 1] as Vector3) + Vector3(0.0, Y_OFFSET, 0.0)
			_mesh.surface_add_vertex(to_local(a))
			_mesh.surface_add_vertex(to_local(b))
			_add_marker(b)
	_mesh.surface_end()


## A small diamond marker at a waypoint, in the same PRIMITIVE_LINES surface as the line
## segments (mirrors WaypointIndicator, which mixes both in one surface).
func _add_marker(a_point_world: Vector3) -> void:
	var p: Vector3 = to_local(a_point_world)
	var r := MARKER_SIZE
	_mesh.surface_add_vertex(p + Vector3(-r, 0.0, 0.0))
	_mesh.surface_add_vertex(p + Vector3(0.0, 0.0, r))
	_mesh.surface_add_vertex(p + Vector3(0.0, 0.0, r))
	_mesh.surface_add_vertex(p + Vector3(r, 0.0, 0.0))
	_mesh.surface_add_vertex(p + Vector3(r, 0.0, 0.0))
	_mesh.surface_add_vertex(p + Vector3(0.0, 0.0, -r))
	_mesh.surface_add_vertex(p + Vector3(0.0, 0.0, -r))
	_mesh.surface_add_vertex(p + Vector3(-r, 0.0, 0.0))
