@tool
class_name ImplosionParticles
extends EmissionParticles

## Snowflakes that gather in a field, collapse into its centre, then blow apart: the Cryogenic
## Implosion's look. While the phases that show it are live the flakes appear one by one over
## the field and hang there, drifting; when the host enters `collapse_phase` every flake already
## out is pulled into the centre, timed to arrive as that phase ends; entering `burst_phase`
## throws them back out.
##
## Cosmetic only: nothing here touches the simulation, so it may read wall-clock particles.

## Radius of the field the flakes appear over, in world units. Match the host's HitShape.
@export var radius: float = 10.0:
	set(value):
		radius = value
		_shape_field()
## Height of the band the flakes hang in, in world units, from the ground up.
@export var band_height: float = 3.0:
	set(value):
		band_height = value
		_shape_field()
## Flakes per square world unit of field.
@export var density: float = 1.5:
	set(value):
		density = value
		_shape_field()
## The phase, relative to the host, whose start pulls every flake into the centre. Empty never
## collapses.
@export var collapse_phase: NodePath
## The phase, relative to the host, whose start throws every flake back out of the centre.
## Empty never bursts.
@export var burst_phase: NodePath

## Fraction of a flake's life spent growing from nothing to full size: the "materialising".
const FADE_IN_FRACTION: float = 0.08
## How much harder the burst throws the flakes out than the collapse pulled them in: enough to
## clear the field's edge well inside the burst phase.
const BURST_TO_COLLAPSE_RATIO: float = 3.0
## Floor on a phase's squared length, so a zero-length phase asks for a large pull rather than
## an infinite one.
const MIN_PULL_SECONDS_SQUARED: float = 0.0001


func _ready() -> void:
	# Each instance shapes and later collapses its own field, so it must not write into the
	# scene's shared material.
	if process_material != null:
		process_material = process_material.duplicate()
	_shape_field()
	if Engine.is_editor_hint():
		return
	var phased: PhasedLocomotion = _phased()
	if phased != null:
		phased.phase_entered.connect(_on_phase_entered)


## Pull every flake into the centre so that one starting at the field's edge arrives in
## `a_seconds`.
func collapse(a_seconds: float) -> void:
	_accelerate_radially(-_edge_to_centre_pull(a_seconds))


## Throw every flake out of the centre, `BURST_TO_COLLAPSE_RATIO` times as hard as a collapse
## over `a_seconds` would pull them in.
func burst(a_seconds: float) -> void:
	_accelerate_radially(_edge_to_centre_pull(a_seconds) * BURST_TO_COLLAPSE_RATIO)


func is_collapsing() -> bool:
	var material := process_material as ParticleProcessMaterial
	return material != null and material.radial_accel_max < 0.0


func is_bursting() -> bool:
	var material := process_material as ParticleProcessMaterial
	return material != null and material.radial_accel_min > 0.0


func _on_phase_entered(a_index: int) -> void:
	var phased: PhasedLocomotion = _phased()
	var host: Node = _host()
	if phased == null or host == null:
		return
	var phase: EmissionPhase = phased.phase_at(a_index)
	if phase == null:
		return
	if not collapse_phase.is_empty() and phase == host.get_node_or_null(collapse_phase):
		collapse(phase.lifespan_seconds)
	elif not burst_phase.is_empty() and phase == host.get_node_or_null(burst_phase):
		burst(phase.lifespan_seconds)


## The emission this draws for: the nearest Entity above it.
func _host() -> Node:
	var node: Node = get_parent()
	while node != null and not (node is Entity):
		node = node.get_parent()
	return node


func _phased() -> PhasedLocomotion:
	var host: Node = _host()
	return host.get_node_or_null("Locomotion") as PhasedLocomotion if host != null else null


## The pull that brings a flake at rest on the field's edge to the centre in `a_seconds`:
## constant acceleration from rest covers radius = ½·a·t².
func _edge_to_centre_pull(a_seconds: float) -> float:
	return 2.0 * radius / maxf(a_seconds * a_seconds, MIN_PULL_SECONDS_SQUARED)


## Hand every flake out already one radial acceleration — positive outward — and nothing else
## to steer it, and stop new ones appearing.
func _accelerate_radially(a_acceleration: float) -> void:
	var material := process_material as ParticleProcessMaterial
	if material == null:
		return
	# The material clamps min ≤ max on every write, so a sign flip written one bound at a time
	# drags the other along with it. Open the range around the target first.
	material.radial_accel_min = minf(material.radial_accel_min, a_acceleration)
	material.radial_accel_max = a_acceleration
	material.radial_accel_min = a_acceleration
	material.tangential_accel_min = 0.0
	material.tangential_accel_max = 0.0
	material.damping_min = 0.0
	material.damping_max = 0.0
	material.turbulence_enabled = false
	emitting = false


func _shape_field() -> void:
	var material := process_material as ParticleProcessMaterial
	if material == null:
		return
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	material.emission_ring_axis = Vector3.UP
	material.emission_ring_radius = radius
	material.emission_ring_inner_radius = 0.0
	material.emission_ring_height = band_height
	if material.scale_curve == null:
		material.scale_curve = _fade_in_curve()
	position.y = band_height * 0.5
	amount = maxi(1, roundi(density * PI * radius * radius))
	var reach: float = radius + 2.0
	visibility_aabb = AABB(
		Vector3(-reach, -band_height, -reach), Vector3(reach * 2.0, band_height * 2.0, reach * 2.0)
	)


static func _fade_in_curve() -> CurveTexture:
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.0))
	curve.add_point(Vector2(FADE_IN_FRACTION, 1.0))
	curve.add_point(Vector2(1.0, 1.0))
	var texture := CurveTexture.new()
	texture.curve = curve
	return texture
