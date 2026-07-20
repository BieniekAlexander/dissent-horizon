class_name MeshVisual
extends Node3D

## MeshVisual — the mesh-based successor to the billboard `Sprite` node.
##
## Owns everything about *how a 3D entity looks and orients visually*, so the
## rest of the entity never touches MeshInstance3D or materials directly:
##   • holds the imported model (instanced as a child of this node),
##   • applies a team-colour tint to the whole mesh (the modulate-equivalent),
##   • faces the model toward a direction (replaces the old Sprite.flip_h),
##   • exposes an animation-state hook (a no-op until an AnimationTree exists).
##
## This is the component the codebase kept foreshadowing as a "SpriteVisual" /
## "SpriteAnimation" owner (see Entity._apply_team_tint and Commandable._process).
## Add it as a child of a Commandable with the model scene parented under it:
##
##     Commandable
##       └── MeshVisual   (this script)
##             └── Model   (instanced .glb / MeshInstance3D)
##
## A MeshVisual does not know about commands, ownership, or movement — callers
## push state to it via set_team_color() / face_direction() / set_animation_state().

#region Constants
## High-level visual states an entity can be in. Maps 1:1 to the AnimationTree
## state machine we'll add later; for now set_animation_state() just records it.
enum AnimationState { IDLE, MOVE, ATTACK, DIE }
#endregion

#region Configuration
## How quickly the model yaws toward a new facing, in radians/second.
## 0 = snap instantly (the default while there's no turn animation to blend).
@export var turn_speed: float = 0.0
#endregion

#region State
var _anim_state: AnimationState = AnimationState.IDLE
var _tint: Color = Color.WHITE
var _opacity: float = 1.0
var _target_yaw: float = 0.0
var _has_target_yaw: bool = false

## One record per tintable surface: {mat: BaseMaterial3D, albedo: Color}. `albedo`
## is the material's *design* colour, captured once, so tint/opacity stay
## non-destructive (we recompute from it rather than reading back a tinted value).
var _surfaces: Array[Dictionary] = []
var _ready_done: bool = false
#endregion

func _ready() -> void:
	_gather_surfaces()
	_target_yaw = rotation.y
	_ready_done = true
	_reapply()

## Walk the model subtree, give every StandardMaterial3D surface a unique
## override material (so we never mutate the shared imported resource), and
## remember its design albedo for non-destructive tinting.
func _gather_surfaces() -> void:
	_surfaces.clear()
	for mi: MeshInstance3D in _find_mesh_instances(self):
		if mi.mesh == null:
			continue
		for s: int in mi.mesh.get_surface_count():
			var src: Material = mi.get_active_material(s)
			if src is BaseMaterial3D:
				var mat: BaseMaterial3D = src.duplicate() as BaseMaterial3D
				mi.set_surface_override_material(s, mat)
				_surfaces.append({"mat": mat, "albedo": mat.albedo_color})
			# ShaderMaterial (or null) surfaces are skipped — tinting those would
			# need a shader uniform. Left for when a custom shader look exists.

func _find_mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node)
	for child: Node in node.get_children():
		out.append_array(_find_mesh_instances(child))
	return out

#region Material — team colour + opacity
## Tint the whole model by `color`, multiplying the design albedo exactly like
## the old Sprite.modulate did. (For an already-coloured mesh this muddies the
## base colours by design; when you want a cleaner result, restrict the tint to a
## dedicated "team" surface — the per-surface structure here already supports it.)
func set_team_color(color: Color) -> void:
	_tint = color
	if _ready_done:
		_reapply()

## Overall opacity in 0..1; enables alpha transparency below 1. Intended for
## build-in progress / stealth fades. Available now, not yet driven by callers.
func set_opacity(a: float) -> void:
	_opacity = clampf(a, 0.0, 1.0)
	if _ready_done:
		_reapply()

func _reapply() -> void:
	for rec: Dictionary in _surfaces:
		var base: Color = rec["albedo"]
		var mat: BaseMaterial3D = rec["mat"]
		mat.albedo_color = Color(
			base.r * _tint.r, base.g * _tint.g, base.b * _tint.b, base.a * _opacity
		)
		mat.transparency = (
			BaseMaterial3D.TRANSPARENCY_ALPHA if _opacity < 1.0
			else BaseMaterial3D.TRANSPARENCY_DISABLED
		)
#endregion

#region Facing
## Yaw the model to look along `dir` (XZ only; Y ignored). With turn_speed 0 the
## change is instant; otherwise _process eases toward it. -Z is the model's
## authored forward (glTF/Godot convention).
func face_direction(dir: Vector3) -> void:
	var flat: Vector2 = Vector2(dir.x, dir.z)
	if flat.length_squared() < 0.0001:
		return
	_target_yaw = atan2(-flat.x, -flat.y)
	_has_target_yaw = true
	if turn_speed <= 0.0:
		rotation.y = _target_yaw

func _process(delta: float) -> void:
	if turn_speed <= 0.0 or not _has_target_yaw:
		return
	var diff: float = wrapf(_target_yaw - rotation.y, -PI, PI)
	var step: float = turn_speed * delta
	rotation.y = _target_yaw if absf(diff) <= step else rotation.y + signf(diff) * step
#endregion

#region Animation
## Record the entity's high-level visual state. No-op until an AnimationTree is
## wired in — at which point this becomes a state-machine travel() call. Kept as
## the single entry point so callers never touch animation nodes directly.
func set_animation_state(state: AnimationState) -> void:
	if state == _anim_state:
		return
	_anim_state = state
	# TODO: when animated models exist, drive an AnimationTree here, e.g.
	#   ($AnimationTree.get("parameters/playback") as AnimationNodeStateMachinePlayback) \
	#       .travel(_STATE_NAMES[state])

func animation_state() -> AnimationState:
	return _anim_state
#endregion
