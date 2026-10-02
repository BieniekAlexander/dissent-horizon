class_name MeshVisual
extends Node3D

## MeshVisual — the mesh-based successor to the billboard `Sprite` node.
##
## Owns everything about *how a 3D entity looks and orients visually*, so the
## rest of the entity never touches MeshInstance3D or materials directly:
##   • holds the imported model (instanced as a child of this node),
##   • applies a team-colour tint to the whole mesh (the modulate-equivalent),
##   • composes the CONSTRUCTION and STATUS channels that fade and darken it,
##   • faces the model toward a direction (replaces the old Sprite.flip_h),
##   • exposes an animation-state hook (a no-op until an AnimationTree exists).
##
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

## The three opacities of the construction lifecycle. Shared by the live entity
## (Commandable._apply_construction_visuals) and by the HUD's ghost copies
## (RTSController's placement preview + blueprints), so a structure reads the same
## everywhere it's drawn:
##   PLANNED      — not on the map at all: the structure under the cursor while the
##                  player aims a Build, or the blueprint marking a site an issued
##                  Build order has claimed but no builder has laid down yet.
##   CONSTRUCTING — placed: a real, collidable structure that isn't finished.
##   BUILT        — finished.
const OPACITY_PLANNED: float = 0.2
const OPACITY_CONSTRUCTING: float = 0.5
const OPACITY_BUILT: float = 1.0

## How dark a blueprint is drawn while its purchase is still WAITING FOR FUNDS — a
## build order the commander has committed to but can't pay for yet (see
## Commandable.awaiting_funds). Multiplies the model's colour, so an unfunded site reads
## as a darker version of the same blueprint rather than as a different thing.
##
## Deliberately a SHADE and not a fourth opacity: the opacity scale already means
## "how far along the construction lifecycle is this", and an unfunded blueprint is at
## the same point on that scale as a funded one — it differs in whether it's PAID FOR,
## which is a separate axis and needs a separate channel to say so.
const SHADE_AWAITING_FUNDS: float = 0.35
const SHADE_NORMAL: float = 1.0

## The STATUS channel's neutral values — what a unit under no condition at all is drawn
## at. A SECOND pair of factors alongside the construction ones above, multiplied into
## the same albedo, because the two answer questions that vary independently: a
## half-built barracks can be EMP'd, and a stealthed unit is no less finished for
## fading. Written by StatusVisuals; construction is written by Commandable.
##   • status opacity — how VISIBLE the entity currently is (the stealth pulse).
##   • status tint    — what colour its condition draws it (an EMP's dead-machine black,
##                      a freeze's cryo blue).
##
## A COLOUR and not a scalar, unlike the construction shade: a shade can only ever say
## "darker", and a freeze has to say "colder" — its whole point is that the unit is being
## ARMOURED, so draining it toward black would read as the opposite of what happened.
const STATUS_OPACITY_NORMAL: float = 1.0
const STATUS_TINT_NORMAL: Color = Color.WHITE
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
var _shade: float = SHADE_NORMAL
var _status_opacity: float = STATUS_OPACITY_NORMAL
var _status_tint: Color = STATUS_TINT_NORMAL
var _target_yaw: float = 0.0
var _has_target_yaw: bool = false

## One record per tintable surface: {mat: BaseMaterial3D, albedo: Color}. `albedo`
## is the material's *design* colour, captured once, so tint/opacity stay
## non-destructive (we recompute from it rather than reading back a tinted value).
var _surfaces: Array[Dictionary] = []
## Every MeshInstance3D under the model, kept so shadow casting can be toggled with
## opacity (a see-through structure that still casts a solid shadow reads as solid).
var _mesh_instances: Array[MeshInstance3D] = []
var _ready_done: bool = false
#endregion


func _ready() -> void:
	_gather_surfaces()
	_target_yaw = rotation.y
	_ready_done = true
	_reapply()


## Walk the model subtree, give every tintable surface a unique override material (so we
## never mutate the shared imported resource), and remember its design albedo for
## non-destructive tinting.
func _gather_surfaces() -> void:
	_surfaces.clear()
	_mesh_instances = _find_mesh_instances(self)
	_silhouette = _wants_obstruction_silhouette()
	for mi: MeshInstance3D in _mesh_instances:
		if mi.mesh == null:
			continue
		for s: int in mi.mesh.get_surface_count():
			var mat: BaseMaterial3D = _tintable_material(mi.get_active_material(s))
			if mat == null:
				continue
			mi.set_surface_override_material(s, mat)
			_surfaces.append({"mat": mat, "albedo": mat.albedo_color})


## The material to tint a surface through, or null when the surface cannot be tinted.
##
## A copy of the surface's own material where it has one, so the shared imported resource is
## never mutated. Where it has NONE, a fresh white StandardMaterial3D: the engine draws an
## unmaterialed surface white anyway, so this changes nothing about how it looks untinted
## and makes it tintable. That is what the generated placeholder models need — bare
## primitives carrying no material, so every commander's stand-ins were coming out the same
## colour, on exactly the pieces with no art to read allegiance from.
##
## ShaderMaterial surfaces are refused: tinting one needs a shader uniform. Left for when a
## custom shader look exists.
func _tintable_material(a_source: Material) -> BaseMaterial3D:
	if a_source is BaseMaterial3D:
		return a_source.duplicate() as BaseMaterial3D
	return StandardMaterial3D.new() if a_source == null else null


func _find_mesh_instances(a_node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if a_node is MeshInstance3D:
		out.append(a_node)
	for child: Node in a_node.get_children():
		out.append_array(_find_mesh_instances(child))
	return out


#region Obstruction silhouette
## "See-through when obstructed": a unit hidden behind a building or a cliff is redrawn
## over it as a flat team-coloured silhouette of its own mesh, so a small model can't be
## swallowed whole by a large one.
##
## This is Godot's built-in x-ray (BaseMaterial3D.STENCIL_MODE_XRAY), NOT a hand-written
## depth-texture comparison, and the difference is not cosmetic. A depth-texture shader
## can only ask "is something nearer than me at this pixel?", which is the wrong question
## twice over:
##   • On an UNOBSTRUCTED unit the depth buffer holds that unit's own opaque draw, so the
##     comparison is a float against itself and rounding decides it — the model renders
##     speckled with silhouette everywhere, on every unit on screen. A bias fixes that.
##   • A bias does NOT fix the rest: a model's own head occludes its own shoulders, so the
##     parts of a unit behind its own geometry keep reading as "obstructed" no matter how
##     the threshold is tuned (removing it needs a bias as deep as the model itself, which
##     would also swallow real obstruction).
## The stencil asks the right question instead — "did MY geometry pass the depth test
## here?" — so the unit's own surfaces can never obstruct it. The surface material marks
## the stencil where it draws; the engine's x-ray pass fills stencil_color wherever the
## geometry rasterizes but that mark is absent, i.e. exactly where something ELSE won.
##
## Needs the Forward+ or Mobile renderer for the stencil buffer (this project is Forward+).
##
## One consequence worth knowing: every silhouette shares the one stencil reference value,
## so a unit hidden behind ANOTHER UNIT is not drawn through it — only terrain and
## structures are seen through. That is the wanted reading (units don't x-ray each other),
## and it falls out for free rather than needing a per-entity reference.

## How solid the silhouette is drawn over whatever is hiding the unit.
const SILHOUETTE_ALPHA: float = 0.55

## Whether this model takes the silhouette at all — decided once in _gather_surfaces, then
## honoured by _reapply on every tint/opacity change.
var _silhouette: bool = false


## Only entities without a Structure component get the see-through treatment when
## obstructed — if one structure obstructs another, that's left to level/mesh design
## rather than drawn around. Entity.structure_is_active() is the fixture test.
func _wants_obstruction_silhouette() -> bool:
	var parent := get_parent() as Entity
	return parent != null and not parent.structure_is_active()


## The stencil setup for one surface. Suppressed while the model is faded: a translucent
## material doesn't write depth, so it can't mark the stencil either, and the x-ray pass
## would then paint the WHOLE model as though it were hidden.
func _apply_silhouette(a_mat: BaseMaterial3D) -> void:
	if not _silhouette or effective_opacity() < 1.0:
		a_mat.stencil_mode = BaseMaterial3D.STENCIL_MODE_DISABLED
		return
	a_mat.stencil_mode = BaseMaterial3D.STENCIL_MODE_XRAY
	# Team colour, not a faction-neutral white: the silhouette should read as "this is MY
	# unit, seen through a wall". Alpha is fixed rather than tracking _opacity — the fade is
	# a construction state, and a faded model has no silhouette at all (see above).
	a_mat.stencil_color = Color(_tint.r, _tint.g, _tint.b, SILHOUETTE_ALPHA)


#endregion


#region Material — team colour + opacity
## Tint the whole model by `color`, multiplying the design albedo exactly like
## the old Sprite.modulate did. (For an already-coloured mesh this muddies the
## base colours by design; when you want a cleaner result, restrict the tint to a
## dedicated "team" surface — the per-surface structure here already supports it.)
func set_team_color(a_color: Color) -> void:
	_tint = a_color
	if _ready_done:
		_reapply()


## Overall opacity in 0..1; enables alpha transparency below 1. Drives the
## construction-state fade (see the OPACITY_* constants) and is the hook for stealth.
func set_opacity(a_a: float) -> void:
	_opacity = clampf(a_a, 0.0, 1.0)
	if _ready_done:
		_reapply()


## The opacity currently applied, as a value in 0..1 — the counterpart of
## animation_state(), so callers (and tests) can read the fade back without touching
## materials.
func opacity() -> float:
	return _opacity


## Darken the whole model by `s` in 0..1 (1 = the model's own colours). A THIRD factor
## alongside the team tint and the opacity, rather than folded into either: the tint has
## to keep saying which side owns this, and the opacity has to keep saying where in the
## construction lifecycle it is, so "not paid for yet" needs its own channel to survive
## underneath both. See SHADE_AWAITING_FUNDS.
func set_shade(a_s: float) -> void:
	_shade = clampf(a_s, 0.0, 1.0)
	if _ready_done:
		_reapply()


## The shade currently applied, in 0..1 — the counterpart of opacity(), so callers and
## tests can read it back without touching materials.
func shade() -> float:
	return _shade


## The STATUS channel's alpha factor, in 0..1 — how visible the entity's CONDITION makes
## it, independent of where it is in the construction lifecycle. 1.0 = the condition asks
## for no fade at all. Written by StatusVisuals (the stealth pulse); a caller wanting the
## construction fade wants set_opacity() instead.
## Unlike the construction setters this one is written EVERY FRAME by StatusVisuals, so
## it returns early on an unchanged value: without that, every entity in the game would
## rewrite all of its surface materials each frame to say nothing had changed.
func set_status_opacity(a_a: float) -> void:
	var v: float = clampf(a_a, 0.0, 1.0)
	if is_equal_approx(v, _status_opacity):
		return
	_status_opacity = v
	if _ready_done:
		_reapply()


func status_opacity() -> float:
	return _status_opacity


## The STATUS channel's RGB factor (white = the model's own colours) — what colour the
## entity's CONDITION draws it. Written by StatusVisuals from the active status effects;
## the construction shade is set_shade().
## Written every frame; early-outs on an unchanged value for the same reason
## set_status_opacity does.
func set_status_tint(a_c: Color) -> void:
	if a_c.is_equal_approx(_status_tint):
		return
	_status_tint = a_c
	if _ready_done:
		_reapply()


func status_tint() -> Color:
	return _status_tint


## The alpha the model is ACTUALLY drawn at: both channels multiplied together. This —
## not opacity() — is what decides transparency and the silhouette, since either channel
## alone dropping below 1.0 makes the material translucent.
func effective_opacity() -> float:
	return _opacity * _status_opacity


## The RGB multiplier the model is ACTUALLY drawn with: the team colour, the construction
## shade and the condition tint, all three together. Alpha is not its business.
func effective_tint() -> Color:
	return Color(
		_tint.r * _shade * _status_tint.r,
		_tint.g * _shade * _status_tint.g,
		_tint.b * _shade * _status_tint.b
	)


func _reapply() -> void:
	var opacity: float = effective_opacity()
	var tint: Color = effective_tint()
	for rec: Dictionary in _surfaces:
		var base: Color = rec["albedo"]
		var mat: BaseMaterial3D = rec["mat"]
		# The colour terms multiply the RGB only. Darkening a blueprint (or an EMP'd tank)
		# must not also make it more (or less) see-through — alpha stays purely the opacity's
		# business, and the two channels compose within each of RGB and alpha separately.
		mat.albedo_color = Color(
			base.r * tint.r, base.g * tint.g, base.b * tint.b, base.a * opacity
		)
		mat.transparency = (
			BaseMaterial3D.TRANSPARENCY_ALPHA
			if opacity < 1.0
			else BaseMaterial3D.TRANSPARENCY_DISABLED
		)
		_apply_silhouette(mat)
	# A translucent model that still casts a filled shadow reads as a solid building,
	# which defeats the whole point of the fade — drop the shadow while faded.
	var shadow: GeometryInstance3D.ShadowCastingSetting = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if opacity < 1.0
		else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	)
	for mi: MeshInstance3D in _mesh_instances:
		if is_instance_valid(mi):
			mi.cast_shadow = shadow


#endregion

#region Extents
## Cached local-space top of the model, in the OWNING ENTITY's frame. NAN = not measured
## yet; measuring needs the node in the tree, so it happens on first request rather than
## in _ready.
var _top_offset: float = NAN


## How far above the entity's origin the model's highest point sits, in the entity's own
## local space. Floating billboards (the veterancy chevrons, the status icons) stack up
## from here, so each piece carries its markers at its own height with nothing authored
## per scene — the HP bar, which predates this, is positioned by hand in every single unit
## scene and is what shows why that is worth avoiding.
##
## Measured once and cached: a model's extents don't change, and an AABB walk is not
## something to run per unit per frame. Returns 0.0 without caching for an entity that has
## no mesh yet or is out of the tree (a build-preview ghost), so a later call still gets a
## real answer.
func model_top_offset() -> float:
	if not is_nan(_top_offset):
		return _top_offset
	var entity: Node3D = get_parent() as Node3D
	if entity == null or not is_inside_tree() or _mesh_instances.is_empty():
		return 0.0
	var to_entity: Transform3D = entity.global_transform.affine_inverse()
	var top: float = 0.0
	for mi: MeshInstance3D in _mesh_instances:
		# Hidden meshes are skipped: measuring to a box nobody can see would float the badges
		# above nothing.
		if not is_instance_valid(mi) or mi.mesh == null or not mi.visible:
			continue
		var local: AABB = (to_entity * mi.global_transform) * mi.get_aabb()
		top = maxf(top, local.position.y + local.size.y)
	_top_offset = top
	return _top_offset


#endregion


#region Descent
## Drop the model onto its spot: start `a_height` above where it rests and settle over
## `a_seconds`, decelerating. Presentation only — the piece is where it is from the start, and
## nothing about it waits for the model to land. Used by a deployment drop.
func play_descent(a_height: float, a_seconds: float) -> void:
	var rest_y: float = position.y
	position.y = rest_y + a_height
	create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT).tween_property(
		self, "position:y", rest_y, a_seconds
	)


#endregion


#region Facing
## Yaw the model to look along `dir` (XZ only; Y ignored). With turn_speed 0 the
## change is instant; otherwise _process eases toward it. -Z is the model's
## authored forward (glTF/Godot convention).
func face_direction(a_dir: Vector3) -> void:
	var flat: Vector2 = Vector2(a_dir.x, a_dir.z)
	if flat.length_squared() < 0.0001:
		return
	_target_yaw = atan2(-flat.x, -flat.y)
	_has_target_yaw = true
	if turn_speed <= 0.0:
		rotation.y = _target_yaw


func _process(a_delta: float) -> void:
	if turn_speed <= 0.0 or not _has_target_yaw:
		return
	var diff: float = wrapf(_target_yaw - rotation.y, -PI, PI)
	var step: float = turn_speed * a_delta
	rotation.y = _target_yaw if absf(diff) <= step else rotation.y + signf(diff) * step


#endregion


#region Animation
## Record the entity's high-level visual state. No-op until an AnimationTree is
## wired in — at which point this becomes a state-machine travel() call. Kept as
## the single entry point so callers never touch animation nodes directly.
func set_animation_state(a_state: AnimationState) -> void:
	if a_state == _anim_state:
		return
	_anim_state = a_state
	# TODO: when animated models exist, drive an AnimationTree here, e.g.
	#   ($AnimationTree.get("parameters/playback") as AnimationNodeStateMachinePlayback) \
	#       .travel(_STATE_NAMES[state])


func animation_state() -> AnimationState:
	return _anim_state
#endregion
