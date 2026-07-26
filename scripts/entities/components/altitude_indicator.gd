class_name AltitudeIndicator
extends Node3D

## Draws an SC2-style ground marker for an airborne unit: a vertical line from the
## unit down to the terrain directly below it, plus a small ring on the surface at
## that point. Makes a flying unit's true ground position readable against the grid.
##
## Sibling of CommandLineIndicator (same recipe: an ImmediateMesh redrawn each
## _process on an unshaded, vertex-coloured material). Lives on the shared
## commandable.tscn base scene; it self-gates, so ground units and structures —
## whose origin already sits on the terrain — draw nothing and pay only an early-out.

#region Constants
## Vertical drop (world units) below which nothing is drawn. A grounded unit's
## origin is snapped onto the terrain each tick, so its drop is ~0.
const MIN_DROP: float = 0.05
## Lift applied to ground geometry to avoid z-fighting with the terrain mesh.
const Y_OFFSET: float = 0.05
## Opacity of the marker (half the original 0.7). The hue comes from the unit's
## team colour; this is the alpha it's drawn at.
const ALPHA: float = 0.2
#endregion

#region Configuration
## Radius (world units) of the ground ring.
@export var ring_radius: float = 0.117
## Segment count of the ground ring.
@export var ring_segments: int = 24
#endregion

#region State
var _mesh: ImmediateMesh
var _mesh_instance: MeshInstance3D
#endregion

#region Lifecycle
func _ready() -> void:
	_mesh = ImmediateMesh.new()
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = _mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mesh_instance.material_override = mat
	add_child(_mesh_instance)

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_redraw()
#endregion

#region Private helpers
func _redraw() -> void:
	_mesh.clear_surfaces()

	var unit := get_parent() as Commandable
	if unit == null or unit.map == null:
		return

	# Ground point directly below the unit, and the drop from origin to it.
	var self_xz: Vector2 = VU.inXZ(unit.global_position)
	var ground_y: float = unit.map.terrain_height_at(self_xz)
	var drop: float = unit.global_position.y - ground_y
	if drop <= MIN_DROP:
		return

	# Match the unit's team colour (same source as Entity._apply_team_tint), drawn
	# at ALPHA opacity.
	var color: Color = Entity.TEAM_COLOR_MAP.get(unit.commander_id, Color.WHITE)
	color.a = ALPHA

	# Vertical line: unit origin (local 0) down to the ground point. to_local keeps
	# it world-vertical despite the parent's yaw / hover tilt.
	var foot: Vector3 = to_local(Vector3(self_xz.x, ground_y + Y_OFFSET, self_xz.y))
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	_mesh.surface_set_color(color)
	_mesh.surface_add_vertex(Vector3.ZERO)
	_mesh.surface_add_vertex(foot)
	_mesh.surface_end()

	# Ground ring: each vertex samples terrain height so it drapes over slopes.
	_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	_mesh.surface_set_color(color)
	for i: int in ring_segments + 1:
		var theta: float = TAU * float(i) / float(ring_segments)
		var ring_xz: Vector2 = self_xz + ring_radius * Vector2(cos(theta), sin(theta))
		var ry: float = unit.map.terrain_height_at(ring_xz) + Y_OFFSET
		_mesh.surface_add_vertex(to_local(Vector3(ring_xz.x, ry, ring_xz.y)))
	_mesh.surface_end()
#endregion
