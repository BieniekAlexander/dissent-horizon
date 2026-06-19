class_name Interaction
extends Resource

## A single interaction an [Interactor]-equipped unit can perform. The unit moves
## into range and "interacts" for `duration` seconds; on completion the `event`
## scene is performed.
##
## Applicability is decided by `type`: each Interaction.Type maps to an
## evaluation function (same signature as Command.meets_precondition) that
## inspects the actor/message and returns whether the interaction may proceed.
## Held in an [Interactor]'s `interactions` list.

#region Types
enum Type {
	## Liberate a producing structure: applicable when the target owns a
	## Production component.
	LIBERATE,
}
#endregion

#region Properties
## Which interaction this is; selects the evaluation function (see _evaluators).
@export var type: Interaction.Type = Interaction.Type.LIBERATE

## Scene performed when the interaction completes. A spawned Entity is placed via
## Map.add_entity (nearest navmesh point, under the actor's commander); other
## scenes are added to the active scene and, if a Event, executed.
@export var event: PackedScene

## Seconds the unit must remain interacting (in range) before completion.
@export var duration: float = 1.0
#endregion

#region Evaluation
## Per-type evaluation functions, each with the same signature as
## Command.meets_precondition: (a_actor, a_message) -> PreconditionFailureCause.
## Built lazily — static-var class-resolution order is fragile at init time.
static var _evaluators: Dictionary

static func _build_evaluators() -> Dictionary:
	return {
		Type.LIBERATE: func(_a_actor: Commandable, a_message: CommandMessage) -> Command.PreconditionFailureCause:
			return Command.PreconditionFailureCause.NONE \
				if is_instance_valid(a_message.target) and a_message.target.has_node("Shelter") \
				else Command.PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE,
	}

static func _evaluator_for(a_type: Interaction.Type) -> Callable:
	if _evaluators.is_empty():
		_evaluators = _build_evaluators()
	return _evaluators[a_type]

## Evaluate this interaction's applicability for the given actor/message, using
## the function mapped to its `type`.
func meets_precondition(
	a_actor: Commandable,
	a_message: CommandMessage
) -> Command.PreconditionFailureCause:
	return _evaluator_for(type).call(a_actor, a_message)
#endregion
