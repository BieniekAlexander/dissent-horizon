class_name Payload
extends Node

## What an emission does to what it reaches: its damage, how it aims, and the status effects
## it carries. It pays out on the live phase's cadence (EmissionPhase.applies_payload,
## payload_period_seconds), which its host's PhasedLocomotion announces each tick.
##
## `hitscan` is the AIMING rule and nothing else: true lands the payload on the piece the shot
## was fired at, false on everything inside the host's HitShape. See
## gdd/systems/combat/projectiles.md §`hitscan` is the aiming rule.

## A payout landed: `a_victims` are the pieces it was applied to, empty when it reached none.
## What a measurement listens to; nothing in the game does.
signal paid_out(a_victims: Array)

#region Properties
## Launch-time spread for a shot aimed at one target: purely cosmetic, since that payload lands
## on `target` wherever the visible shot went, so it can never cause a miss.
const HITSCAN_MAX_ERROR_ANGLE: float = deg_to_rad(2.0)

@export var hitscan: bool = false
## Aim at the GROUND under a BIO target rather than at the target: the shot lands where the
## soldier stood when it was fired, and misses a soldier who has moved out of its blast. A MECH
## target is still pursued. Doc key `bio_ground_aim:`; meaningless on a hitscan shot, which
## lands on its target whatever it hits. See projectiles.md §Free flight.
@export var bio_ground_aim: bool = false
## Damage applied per payout, before veterancy and the damage table.
@export var base_damage: float = 5.0
@export var damage_type: Damage.Type = Damage.Type.LEAD

## Who fired it — the attribution for damage and effects. May be freed mid-flight.
var from: Actor
## What it was aimed at, or what an impact test found instead. May be freed mid-flight.
var target: Entity
## A blast's victims, measured on the tick of the last contact and waiting for the payout that
## follows it. Untyped: a victim may be freed before then, and a freed object fails a typed
## array's element check.
var _contact_victims: Array = []
var _has_contact_victims: bool = false
#endregion


#region Public API
## `a_node`'s Payload component, or null. Untyped because a caller may hold a freed reference.
static func of(a_node: Variant) -> Payload:
	if a_node == null or not is_instance_valid(a_node) or not (a_node is Node):
		return null
	return (a_node as Node).get_node_or_null("Payload") as Payload


func host() -> Entity:
	return get_parent() as Entity


## The blast volume, or null for a payload aimed at one piece.
func hit_shape() -> CollisionShape3D:
	return host().get_node_or_null("HitShape") as CollisionShape3D


## Whether this payload lands on an AREA rather than on the single piece it was aimed at: it
## does exactly when the host carries a HitShape, which only a non-hitscan emission has.
func has_blast() -> bool:
	return hit_shape() != null


func get_effects() -> Array:
	return host().get_children().filter(func(child): return child is EffectApplicator)


## Whether a shot at `a_target` is aimed at the ground under it rather than at it.
func aims_at_ground_under(a_target: Entity) -> bool:
	return (
		bio_ground_aim
		and not hitscan
		and a_target.defense != null
		and a_target.defense.frame_type == Defense.FrameType.BIO
	)


## Take aim: `a_from` fired it at `a_target`.
func arm(a_from: Actor, a_target: Entity) -> void:
	from = a_from
	target = a_target


## Rotate a single-target shot's launch velocity by a small random yaw around +UP. Drawn from
## `SU.rng`, the one seeded gameplay generator, so a scenario replays the same spread (see
## gdd/systems/ai/selfplay-harness.md §Determinism).
func aim_error(a_velocity: Vector3) -> Vector3:
	return a_velocity.rotated(
		Vector3.UP, SU.rng.randf_range(-HITSCAN_MAX_ERROR_ANGLE, HITSCAN_MAX_ERROR_ANGLE)
	)


## Pay out once: on the target, or on everything in the blast.
func apply() -> void:
	var damage: Damage = Damage.new(_effective_damage(), damage_type)
	# `from` and `target` can each be freed before this lands, and a freed object fails a
	# typed parameter's class check (CLAUDE.md §A freed object cannot be passed to a typed
	# parameter), so both are guarded. The source collapses to null: an unattributed hit.
	var source: Actor = from if is_instance_valid(from) else null
	if not has_blast():
		# A target that garrisoned mid-flight is alive but out of the world, and out of reach.
		if is_instance_valid(target) and target.is_inside_tree():
			target.receive_damage(damage, source)
			for effect: EffectApplicator in get_effects():
				effect.apply([target], source)
			paid_out.emit([target])
		else:
			paid_out.emit([])
		return
	var victims: Array[Entity] = (
		_take_contact_victims() if _has_contact_victims else _blast_victims()
	)
	for victim: Entity in victims:
		if victim.defense != null:
			victim.receive_damage(damage, source)
	for effect: EffectApplicator in get_effects():
		effect.apply(victims, source)
	paid_out.emit(victims)


#endregion


#region Lifecycle
func _ready() -> void:
	# The importer keeps the two in step; a scene that disagrees was edited by hand.
	if hitscan == has_blast():
		push_error(
			(
				(
					"Emission '%s': hitscan is %s but it %s a HitShape — hitscan aims at one"
					+ " piece, a HitShape is a blast"
				)
				% [host().id, hitscan, "carries" if has_blast() else "has no"]
			)
		)
	var phased: PhasedLocomotion = _phased()
	if phased != null:
		phased.phase_ticking.connect(_on_phase_ticking)
		phased.struck.connect(_on_struck)


#endregion


#region Private helpers
## The host's phased locomotion, found by name: the host's own reference to it is not yet set
## while its children are readying.
func _phased() -> PhasedLocomotion:
	return host().get_node_or_null("Locomotion") as PhasedLocomotion


func _on_phase_ticking(a_phase: EmissionPhase) -> void:
	var phased: PhasedLocomotion = _phased()
	if a_phase.applies_payload and phased.is_on_cadence(a_phase.payload_period_ticks()):
		apply()


## A single-target shot lands on what its impact test struck as if that were its target — a
## targetable piece takes the payload, terrain absorbs it. A blast pays out on its volume
## wherever the contact left it, so the target is irrelevant — and WHO is in that volume is
## decided now, on the contact's own tick, not when the burst phase pays out a tick later: a
## target moving faster than the blast is wide would otherwise be struck and left unharmed
## (projectiles.md §The blast is measured at the contact).
func _on_struck(a_collider: Object) -> void:
	if has_blast():
		_contact_victims = _blast_victims()
		_has_contact_victims = true
		return
	target = Entity.entity_from_collider(a_collider)
	var phased: PhasedLocomotion = _phased()
	phased.set_goal(phased.goal_position, phased.goal_arrival, target)


## Everything a blast here would reach, right now.
func _blast_victims() -> Array[Entity]:
	# UPRIGHT, whatever the emission's pitch: a blast library shape may be a tall cylinder (one
	# that reaches aircraft), and tilting it with a diving shell would sweep a line.
	var shape: CollisionShape3D = hit_shape()
	var blast_xform: Transform3D = shape.global_transform
	blast_xform.basis = Basis.from_scale(blast_xform.basis.get_scale())
	return SU.query_shape_for_entities(
		host().get_world_3d(),
		shape.shape,
		blast_xform,
		CollisionLayers.TARGETABLE_ANY,
		[host()],
		32
	)


## The victims measured at the last contact, once: the first payout after a contact lands on
## them, and any later one (a lingering field's cadence) measures the world as it is. Pieces
## freed or taken out of the world since the contact are dropped.
func _take_contact_victims() -> Array[Entity]:
	var victims: Array[Entity] = []
	_has_contact_victims = false
	for victim: Variant in _contact_victims:
		if is_instance_valid(victim) and (victim as Entity).is_inside_tree():
			victims.append(victim)
	_contact_victims = []
	return victims


## base_damage scaled by the firing unit's veterancy: (1 + level/10), level being the
## Veterancy.Level enum value (0 = NONE … 3 = HEROIC). base_damage alone when the source is
## unknown, freed, or carries no Veterancy.
func _effective_damage() -> float:
	if is_instance_valid(from) and from.veterancy != null:
		return base_damage * (1.0 + float(from.veterancy.level) / 10.0)
	return base_damage
#endregion
