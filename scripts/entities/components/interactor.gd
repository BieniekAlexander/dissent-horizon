class_name Interactor
extends Node

## Interactor component — lists the [Interaction]s a unit can perform. Command
## resolution consults this component to decide whether a unit can [Interact]
## with a given target: each listed interaction is evaluated via its type's
## mapped precondition function (see Interaction.meets_precondition), and the
## first one that passes wins.

#region Properties
## The interactions this unit is capable of, authored per unit scene.
@export var interactions: Array[Interaction] = []
#endregion

#region Public API
## The first listed interaction whose evaluation passes (returns NONE) for the
## given actor/message, or null when none applies.
func applicable_interaction(a_actor: Commandable, a_message: CommandMessage) -> Interaction:
	for interaction: Interaction in interactions:
		if interaction != null \
				and interaction.meets_precondition(a_actor, a_message) == Command.PreconditionFailureCause.NONE:
			return interaction
	return null

## True when this interactor has an interaction applicable to the actor/message.
func can_interact(a_actor: Commandable, a_message: CommandMessage) -> bool:
	return applicable_interaction(a_actor, a_message) != null
#endregion
