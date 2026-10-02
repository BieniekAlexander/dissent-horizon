class_name Interaction
extends Resource

## A single interaction an [Interactor]-equipped unit can perform. The unit moves
## into range and "interacts" for `duration` seconds; on completion the interaction's
## effect runs (see [Interact] for the per-type completion logic).
##
## Applicability is decided by `type`: each Interaction.Type maps to an
## evaluation function (same signature as MoveCommand.meets_precondition) that
## inspects the actor/message and returns whether the interaction may proceed.
## Held in an [Interactor]'s `interactions` list.

#region Types
## Values are stated explicitly: an Interaction's `type` is stored in authored scenes as a
## NUMBER, so a member removed from the middle would silently re-point every one of them.
## (Removing ABDUCT — abduction became a crush, see Garrison.can_capture — cost exactly that
## renumbering, done by hand across three scenes.)
enum Type {
	## Hand the actor's captives over to the target's [Garrison] (e.g. a Compound), which
	## SENTENCES each one as it takes it (see Garrison.deposit_from). Applicable when the
	## actor holds occupants and the target is a structure whose garrison sentences its
	## occupants — i.e. names a positive `sentence_length` — and has room. Transfers as many
	## as fit (partial allowed).
	DEPOSIT = 0,
	# 1 was PLANT, retired for the Plant ability (planted-explosives.md). Left unused rather
	# than reused, for the renumbering reason above.
	## Take a MECH-frame UNIT over: on completion the target changes ownership to the
	## actor's commander and the ACTOR is expended (see Interact._hijack). Applicable to a
	## non-friendly, MECH-frame, non-structure Commandable.
	##
	## Deliberately units-only: a building changing hands
	## is Capture's job, and it has completely different bookkeeping (structure registry,
	## infrastructure, grid). Non-friendly rather than enemy-only — a derelict
	## neutral vehicle is a legitimate prize.
	HIJACK = 2,
}

## How an interaction's duration is derived (see required_ticks):
## - CONSTANT: a fixed `duration` (in seconds).
## - BY_HP: proportional to the target's current hp — a tougher target takes longer
##   to work on (e.g. taking over a bigger vehicle).
enum DurationType { CONSTANT = 0, BY_HP = 1 }
#endregion

#region Properties
## Which interaction this is; selects the evaluation function (see _evaluators).
@export var type: Interaction.Type = Interaction.Type.DEPOSIT

## How this interaction's duration is derived. CONSTANT uses `duration` directly;
## BY_HP scales with the target's current hp (see required_ticks).
@export var duration_type: DurationType = DurationType.CONSTANT

## For CONSTANT duration_type: seconds the unit must remain interacting (in range)
## before completion. Ignored when duration_type is BY_HP.
@export var duration: float = 1.0

## For BY_HP duration_type: physics ticks required per unit of the target's current hp.
## required_ticks returns hp_factor × target.defense.hp.
@export var hp_factor: float = 0.2

## The reach volume the actor uses to contact a MOBILE target, centred (upright) on the
## actor: the interaction can proceed once the target's targetable body overlaps this
## shape. Replaces the former scalar `interact_range`, so reach can be non-circular and
## have vertical extent (a Cylinder height=5 radius=r reproduces the old radius-r reach
## while also tolerating a height gap). Null = the default near-touch contact. Matters
## for unit targets (e.g. HIJACK): RVO avoidance keeps units apart, so a touch-only reach
## makes a mobile target impossible to catch — give such an interaction a shape with some
## radius so it can be performed without colliding. Ignored for structure targets, which use
## footprint
## adjacency regardless.
@export var interact_shape: Shape3D
#endregion

#region Stagger
## Interaction types whose completion is suppressed while the actor is staggered
## (recently damaged): the actor moves into range but waits until the stagger wears off.
## Types not listed (DEPOSIT) proceed regardless. Consulted by
## Interact.blocked_by_stagger via the resolved interaction.
const _STAGGER_BLOCKED_TYPES: Array[Type] = [Type.HIJACK]


## Whether this interaction's completion is blocked while the actor is staggered.
func blocks_while_staggered() -> bool:
	return type in _STAGGER_BLOCKED_TYPES


#endregion


#region Helpers
## The Garrison component on `target`, or null. The deposit target (e.g. a
## Compound) interns the carrier's captives into this.
static func target_garrison(target: Node) -> Garrison:
	return target.get_node_or_null("Garrison") as Garrison if target != null else null


## Physics ticks the actor must remain interacting before this interaction completes,
## resolved against duration_type:
## - CONSTANT: `duration` seconds converted to ticks via the physics tick rate.
## - BY_HP: hp_factor × the target's current hp (a tougher target takes proportionally
##   longer). Falls back to the CONSTANT value when the target has no Defense.
func required_ticks(a_target: Entity) -> float:
	if (
		duration_type == DurationType.BY_HP
		and is_instance_valid(a_target)
		and a_target.defense != null
	):
		return hp_factor * a_target.defense.hp
	return duration * Engine.physics_ticks_per_second


#endregion

#region Evaluation
## Per-type evaluation functions, each with the same signature as
## MoveCommand.meets_precondition: (a_actor, a_message) -> PreconditionFailureCause.
## Built lazily — static-var class-resolution order is fragile at init time.
static var _evaluators: Dictionary


static func _build_evaluators() -> Dictionary:
	return {
		Type.DEPOSIT: _deposit_precondition,
		Type.HIJACK: _hijack_precondition,
	}


## Deposit into a structure whose garrison SENTENCES its occupants — one that names a
## positive sentence_length (Garrison.can_intern) — when we are holding captives and
## it has room. That is what marks a prison (a Compound) apart from an ordinary
## garrison; prisoners are not dropped off in a safehouse.
static func _deposit_precondition(
	a_actor: Commandable, a_message: CommandMessage
) -> MoveCommand.PreconditionFailureCause:
	return (
		MoveCommand.PreconditionFailureCause.NONE
		if (
			is_instance_valid(a_message.target)
			and a_message.target.structure_is_active()
			and a_actor.garrison != null
			and a_actor.garrison.garrisoned_count() > 0
			and target_garrison(a_message.target) != null
			and target_garrison(a_message.target).can_intern()
		)
		else MoveCommand.PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
	)


## Take over a MECH-frame UNIT. Non-friendly (so neutral vehicles qualify too) and
## non-structure, mirroring the capture rule the Stock Truck runs on, with the frame axis
## flipped: a capture takes the crew, HIJACK takes the machine. Structures are excluded
## outright; a building changing hands is Capture, which has its own registry /
## infrastructure / grid bookkeeping.
static func _hijack_precondition(
	a_actor: Commandable, a_message: CommandMessage
) -> MoveCommand.PreconditionFailureCause:
	return (
		MoveCommand.PreconditionFailureCause.NONE
		if (
			is_instance_valid(a_message.target)
			and a_message.target is Commandable
			and not a_message.target.is_friendly_to(a_actor)
			and not a_message.target.structure_is_active()
			and PlantedCharge.of(a_message.target) == null
			and a_message.target.defense != null
			and a_message.target.defense.frame_type == Defense.FrameType.MECH
		)
		else MoveCommand.PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
	)


static func _evaluator_for(type: Interaction.Type) -> Callable:
	if _evaluators.is_empty():
		_evaluators = _build_evaluators()
	return _evaluators[type]


## Evaluate this interaction's applicability for the given actor/message, using
## the function mapped to its `type`.
func meets_precondition(
	a_actor: Commandable, a_message: CommandMessage
) -> MoveCommand.PreconditionFailureCause:
	return _evaluator_for(type).call(a_actor, a_message)
#endregion
