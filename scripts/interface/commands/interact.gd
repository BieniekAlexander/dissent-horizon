class_name Interact
extends MoveCommand

## Generalised interaction command. A unit carrying an [Interactor] component can
## Interact with any target one of its [Interaction]s applies to. The unit moves into
## range, "interacts" for the interaction's `duration`, then the interaction's
## completion effect runs (see _complete).
##
## Replaces the former per-type PickUp / DropOff / Lab-collect special cases:
## what a unit can interact with now lives entirely in its Interactor's list.

#region Properties
## Physics ticks spent interacting so far. Accumulates each tick the unit is in range
## (i.e. while can_act is true, so fulfill_action runs once per physics tick), and the
## interaction completes once it reaches the resolved Interaction's required_ticks.
var _elapsed_ticks: float = 0.0
#endregion

#region Preconditions
static func requires_position() -> bool:
	return true

## Valid when the actor has an Interactor with an applicable interaction (per the
## interaction type's mapped precondition).
static func meets_precondition(
	actor: Commandable,
	message: CommandMessage
) -> PreconditionFailureCause:
	if not is_instance_valid(message.target) or not (message.target is Entity):
		return PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
	if actor.interactor == null or not actor.interactor.can_interact(actor, message):
		return PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
	return PreconditionFailureCause.NONE
#endregion

#region Private helpers
## The interaction the actor would perform on the current target, or null.
func _interaction_for(a_actor: Commandable) -> Interaction:
	if a_actor.interactor == null:
		return null
	return a_actor.interactor.applicable_interaction(a_actor, message)
#endregion

#region State updates
## Some interactions are channeled/vulnerable (HIJACK) and pause while the actor is
## staggered; others (DEPOSIT) are not. Defer to the resolved interaction's own
## rule — see Interaction.blocks_while_staggered.
func blocked_by_stagger(a_actor: Commandable) -> bool:
	var interaction := _interaction_for(a_actor)
	return interaction != null and interaction.blocks_while_staggered()

## Drop the command if the target vanished or the interaction no longer applies.
func get_updated_state(a_actor: Commandable) -> Variant:
	if not is_instance_valid(message.target):
		return null
	if _interaction_for(a_actor) == null:
		return null
	return self

func should_move(a_actor: Commandable) -> bool:
	return is_instance_valid(message.target) and not _in_reach(a_actor)

## Interact travels in order to ACT in range — deposit, plant, hijack — arriving is never
## the point of it. Without this, a truck (or technician, or saboteur) that had to WALK to
## its target lost the order the instant navigation reported it had arrived, whenever that
## happened even one tick before `_in_reach` agreed: it stopped at the target and did
## nothing, holding its cargo/charge/order forever. Same bug, same fix, as Build/Assemble/
## Repair — see CLAUDE.md §Command system and MoveCommand.ends_on_arrival.
func ends_on_arrival() -> bool:
	return false

func can_act(a_actor: Commandable) -> bool:
	return is_instance_valid(message.target) and _in_reach(a_actor)

## A deposit is unloading captives; every other interaction is interacting.
func acting_action(a_actor: Commandable) -> ActionTracker.Action:
	var interaction: Interaction = _interaction_for(a_actor)
	return ActionTracker.Action.UNLOADING \
		if interaction != null and interaction.type == Interaction.Type.DEPOSIT \
		else ActionTracker.Action.INTERACTING

## Whether the actor is close enough to the target to perform the interaction.
## Structure targets always use footprint adjacency (scale- and size-class-aware). For a
## MOBILE target, the resolved interaction's `interact_shape` (a collision volume centred
## on the actor) decides reach when set — letting an interaction (e.g. HIJACK) reach a
## target a few units away without colliding — otherwise the default near-touch contact applies.
func _in_reach(a_actor: Commandable) -> bool:
	var target: Entity = message.target
	if target.is_in_group("fixture"):
		return SU.unit_is_close_to_structure(a_actor, target)
	var interaction := _interaction_for(a_actor)
	if interaction != null and interaction.interact_shape != null:
		return SU.unit_shape_overlaps_target(a_actor, target, interaction.interact_shape)
	return SU.unit_is_close_to_target(a_actor, target)

## Accumulate interaction time while in range; perform the event once the
## interaction's duration has elapsed, then end the command.
func fulfill_action(a_actor: Commandable) -> Variant:
	var interaction := _interaction_for(a_actor)
	if interaction == null:
		return null
	_elapsed_ticks += 1.0
	if _elapsed_ticks < interaction.required_ticks(message.target):
		return self
	_complete(a_actor, interaction)
	return null

## Run the interaction's completion effect, dispatched by type. DEPOSIT moves what the
## actor holds into the target's Garrison; HIJACK takes the target over.
func _complete(a_actor: Commandable, a_interaction: Interaction) -> void:
	match a_interaction.type:
		Interaction.Type.DEPOSIT:
			_deposit(a_actor)
		Interaction.Type.HIJACK:
			_hijack(a_actor)

## Take the targeted vehicle over: it changes hands to the actor's commander, and the
## actor is expended doing it.
##
## Why it works this way: gdd/systems/commands/construction.md §Hijack: taking an occupied vehicle.
func _hijack(a_actor: Commandable) -> void:
	if not is_instance_valid(message.target):
		return
	var prize: Commandable = message.target as Commandable
	if prize == null or a_actor.commander == null:
		return
	prize.update_commands(null)
	prize.commander = a_actor.commander
	if a_actor.defense != null:
		a_actor.defense.kill()


## Move the actor's captives into the target's Garrison, oldest first, until the target is
## full or the actor is empty (partial deposit allowed). A transfer, not a conversion: each
## captive stays itself and starts serving `sentence_length` in the sink — see
## Garrison.deposit_from.
func _deposit(a_actor: Commandable) -> void:
	var source: Garrison = a_actor.garrison
	var sink: Garrison = Interaction.target_garrison(message.target)
	if source == null or sink == null:
		return
	sink.deposit_from(source)
#endregion

#region Debug
func _to_string() -> String:
	return "Interact: %s" % message.position
#endregion
