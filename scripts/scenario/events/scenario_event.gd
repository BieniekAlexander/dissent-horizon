@tool
class_name ScenarioEvent
extends Node3D

## Base class for scenario events. Events are positioned Node3Ds: an event's
## global_position is its anchor (e.g. EventSpawnUnits spawns at that point), and
## child nodes (see EventCommandPoint) describe follow-up behaviour. A Trigger
## holds references to the event nodes it fires when its conditions are met.
##
## Subclasses override execute() for runtime behaviour and, optionally,
## _draw_editor_gizmo() to visualise themselves while editing the scene.

#region Constants
## Colour used for this event's editor gizmo lines.
const _GIZMO_COLOR := Color(1.0, 0.55, 0.1, 0.9)
#endregion

#region Properties
var _gizmo: MeshInstance3D
var _gizmo_material: StandardMaterial3D
#endregion

#region Public API
## Called when an owning Trigger fires. Implement effects in subclasses.
func execute(_manager: ScenarioEventManager) -> void:
	pass
#endregion

#region Lifecycle
func _process(_delta: float) -> void:
	# Editor-only authoring aid: rebuild the gizmo every frame so it tracks the
	# node (and its children) as they're dragged around. The HeightPin tools use
	# the same "@tool node draws helper visuals, skip them at runtime" pattern.
	if Engine.is_editor_hint():
		_refresh_editor_gizmo()
#endregion

#region Editor gizmo
## Override to append this event's gizmo line vertices (in pairs) to `verts`.
## Positions are LOCAL to this node. Default draws nothing.
func _draw_editor_gizmo(_verts: PackedVector3Array) -> void:
	pass


func _refresh_editor_gizmo() -> void:
	if _gizmo == null or not is_instance_valid(_gizmo):
		_gizmo = MeshInstance3D.new()
		_gizmo.mesh = ImmediateMesh.new()
		_gizmo_material = StandardMaterial3D.new()
		_gizmo_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_gizmo_material.vertex_color_use_as_albedo = true
		_gizmo_material.no_depth_test = true
		_gizmo.material_override = _gizmo_material
		# Don't persist or export the helper; it's rebuilt on demand in-editor.
		add_child(_gizmo, false, Node.INTERNAL_MODE_BACK)

	var verts := PackedVector3Array()
	_draw_editor_gizmo(verts)

	var im := _gizmo.mesh as ImmediateMesh
	im.clear_surfaces()
	# surface_end() errors on an empty surface, so skip events that draw nothing.
	if verts.is_empty():
		return
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	im.surface_set_color(_GIZMO_COLOR)
	for v: Vector3 in verts:
		im.surface_add_vertex(v)
	im.surface_end()


## Helper: append a horizontal (XZ) ring of `radius` centred at local `center`.
func _gizmo_ring(verts: PackedVector3Array, center: Vector3, radius: float, segments: int = 24) -> void:
	var prev := center + Vector3(radius, 0.0, 0.0)
	for i in range(1, segments + 1):
		var a: float = TAU * float(i) / float(segments)
		var cur := center + Vector3(cos(a) * radius, 0.0, sin(a) * radius)
		verts.append(prev)
		verts.append(cur)
		prev = cur


## Helper: append a polyline through `points` (local space).
func _gizmo_polyline(verts: PackedVector3Array, points: Array[Vector3]) -> void:
	for i in range(points.size() - 1):
		verts.append(points[i])
		verts.append(points[i + 1])
#endregion
