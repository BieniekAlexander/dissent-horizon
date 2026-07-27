class_name Train
extends MoveCommand

## Which units a producer can train is no longer answered here — that capability
## now lives on the Production component (see production.gd `producible_types` /
## `can_produce`), configured per structure scene. CommandContextParser inspects
## the entity's Production node to build the train menu, so this command class
## carries only the train action's behavior.

#region Preconditions
static func requires_position() -> bool:
	## Indicates whether this command requires a specified position to be issued
	return false

## An actor may take a Train order when it produces the selected type and the
## commander's tech prerequisites are met. Two things are deliberately NOT checked,
## because the production queue waits both of them out rather than refusing the order:
##   * affordability — an unaffordable unit is queued and trained when the energy arrives,
##     BUT only with the additive modifier held: `a_message.defer_if_unaffordable` gates it, so
##     outside that mode an unaffordable order is refused here like any other precondition
##     failure. The default is true, so non-HUD callers are unaffected;
##   * construction   — a structure that is still going up accepts orders too, and the
##     queue hands them over the moment it finishes (see ProductionQueue._dispatch).
##
## This is also what filters a mixed selection down to the actual producers — the
## controller submits ONE purchase per click, listing every capable structure as a
## candidate, so a stronghold+infantry selection trains from the stronghold alone.
static func meets_precondition(
	actor: Commandable,
	message: CommandMessage
) -> PreconditionFailureCause:
	if message.tool == null:
		return PreconditionFailureCause.COMMAND_PENDING_TOOL
	if actor == null or actor.production == null \
			or not actor.production.can_produce(message.tool.type):
		return PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
	if actor.commander == null:
		return PreconditionFailureCause.NONE
	# Ordering at a blueprint whose own BUILD has not been paid for yet is itself a
	# deferral, and a deeper one than an unaffordable price: this unit cannot be produced
	# until that structure is funded, built, AND finished. With no modifier held it is
	# refused for the same reason an unaffordable unit is — the player asked for something
	# to happen now, and nothing about it can happen now. With the modifier it queues, and
	# dispatch holds it until the structure is genuinely ready (ready_producers()).
	#
	# A blueprint whose build IS funded stays orderable, which is the deliberate feature:
	# queuing units at a building the builder is still walking to costs nothing but time.
	if not message.defer_if_unaffordable and actor.awaiting_funds:
		return PreconditionFailureCause.NOT_ENOUGH_ENERGY
	var blocking: TechnologySpec.UnmetNeed = actor.commander.get_blocking_need(
		message.tool.type, message.defer_if_unaffordable
	)
	return unmet_need_to_precondition[blocking]

## Whether `a_producer` has somewhere to put the aircraft `a_tool` would build.
##
## Why it works this way: gdd/systems/combat/aerial-operations/docking-bays-and-pads.md §A pad must be free before an aircraft is trained.
static func has_free_pad_for(producer: Commandable, tool: Tool) -> bool:
	if tool == null or not tool.needs_docking:
		return true
	var bay: DockingBay = producer.get_node_or_null("DockingBay") as DockingBay
	if bay == null:
		return true
	return bay.has_free_pad()
#endregion
