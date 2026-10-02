class_name TaskShelter
extends MoveCommand

## A STANDING order: a Stock Truck tasked on a Shelter keeps working it — collecting each
## new resident and running it to a Compound — until a direct player order replaces this
## command outright. NEVER ENDS ITSELF. See gdd/systems/commands/unit-tasking.md.
##
## "A task is a command with the ending removed" — and that is the whole implementation.
## `get_updated_state` pushes the next errand (a plain move at a resident, or an Interact
## DEPOSIT at a Compound) by returning a DIFFERENT command object; `CommandReceiver`'s
## existing reactive-swap path (the five-step lifecycle, CLAUDE.md §Command system) then
## PREPENDS this task into the unit's queue behind that errand on its own, so it resumes
## automatically once the errand ends — no bespoke queue handling lives here at all. A
## direct player order (any ordinary, non-additive issuance) clears BOTH the active command
## and the queue, so it removes the task and whatever errand it was mid-pushing alike — the
## queue's existing replacement rule, not a special case for this command.

#region Properties
## This task's place in ITS COMMANDER's issue order — stamped by
## RTSController.assign_command_to_units at the moment the order is handed to this unit,
## never by this class itself: sequencing is a fact about WHEN an order was given, not
## about the order. See Commander.trucks_tasked_on — the earliest sequence among a
## commander's live claimants on one Shelter is the only one allowed to chase a resident.
var sequence: int = 0
#endregion


#region Preconditions
static func requires_position() -> bool:
	return true


## Valid for any actor with a Garrison that can hold captives at all, aimed at an Entity
## carrying a Shelter component. Room right now is NOT asked here — the task manages that
## itself, tick to tick, exactly as an empty-handed truck still accepts the order and simply
## holds until a resident appears.
static func meets_precondition(
	actor: Commandable, message: CommandMessage
) -> PreconditionFailureCause:
	if (
		actor == null
		or not is_instance_valid(actor)
		or actor.garrison == null
		or actor.garrison.capacity <= 0
	):
		return PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
	if not is_instance_valid(message.target) or message.target.get_node_or_null("Shelter") == null:
		return PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
	return PreconditionFailureCause.NONE


#endregion


#region State updates
## Never ends on its own (see the class doc). Pushes the next errand when one applies;
## holds — returns self, unchanged — otherwise.
func get_updated_state(a_actor: Commandable) -> Variant:
	if not is_instance_valid(message.target):
		return self  # the Shelter itself is gone; hold until re-tasked or replaced
	var shelter := message.target.get_node_or_null("Shelter") as Shelter
	if shelter == null:
		return self
	var errand: MoveCommand = _next_errand(a_actor, shelter)
	return errand if errand != null else self


## Never acts on its own account — everything this command does to the world happens
## through whatever errand it pushes.
func can_act(_a_actor: Commandable) -> bool:
	return false


## A HOLDING truck goes back to its Shelter and waits there, rather than standing wherever its
## last errand left it — usually beside the Compound it just emptied into, the far end of the
## route. Waiting at the Shelter puts it on the spot for the next resident. Movement goes to
## the Shelter's approach cell (CommandReceiver._resolve_movement_target, as for any
## structure target), and stops once the truck is close by the same rule an errand would use.
func should_move(a_actor: Commandable) -> bool:
	return (
		is_instance_valid(message.target)
		and not SU.unit_is_close_to_target(a_actor, message.target)
	)


## Arrival has no meaning for an order with no destination of its own to reach.
func ends_on_arrival() -> bool:
	return false


#endregion


#region Private helpers
## The next errand this truck should be pushed onto, or null to hold. See the table in
## gdd/systems/commands/unit-tasking.md §The Stock Truck's task.
func _next_errand(a_actor: Commandable, a_shelter: Shelter) -> MoveCommand:
	if not a_actor.garrison.can_garrison():
		return _errand_to_deposit(a_actor)
	return _errand_to_resident(a_actor, a_shelter)


## "no room aboard" -> the nearest Compound (of this actor's commander) that can take a
## deposit and has room; null to hold if none does. A plain Interact — the ordinary DEPOSIT
## order — walks there and deposits on its own; nothing bespoke is needed once it is pushed.
func _errand_to_deposit(a_actor: Commandable) -> MoveCommand:
	var compound: Commandable = _nearest_available_compound(a_actor)
	if compound == null:
		return null
	return Interact.new(CommandMessage.new(message.map, compound))


## "room aboard, a resident is available, and this truck is the earliest-tasked truck of
## its commander's on this Shelter" -> go take that resident. Arbitration is by TASK AGE,
## never by distance: Commander.trucks_tasked_on is sorted oldest-first, so the earliest
## LIVE claimant with room is the only one that ever receives this errand — the rest hold
## until its claim lapses (fills, dies, is re-tasked) and the next in line becomes earliest.
## A plain move IS the capture order (see gdd/systems/combat/garrison-and-transport.md
## §Capture is a crush) — nothing more needs pushing.
func _errand_to_resident(a_actor: Commandable, a_shelter: Shelter) -> MoveCommand:
	if a_shelter.resident_count() == 0 or a_actor.commander == null:
		return null
	var contenders: Array[Commandable] = a_actor.commander.trucks_tasked_on(message.target).filter(
		func(t: Commandable) -> bool: return t.garrison != null and t.garrison.can_garrison()
	)
	if contenders.is_empty() or contenders[0] != a_actor:
		return null
	var resident: Commandable = a_shelter.residents()[0]
	return MoveCommand.new(CommandMessage.new(message.map, resident))


## The nearest Compound belonging to `a_actor`'s commander that takes a deposit and has
## room, or null. Reuses Commander.get_deposit_structures, the same question the bot's
## opportunist asks, so a future holding structure is picked up here with no change either.
func _nearest_available_compound(a_actor: Commandable) -> Commandable:
	if a_actor.commander == null:
		return null
	return SU.nearest_of(a_actor.commander.get_deposit_structures(), a_actor)


#endregion


#region Debug
func _to_string() -> String:
	return "TaskShelter: %s" % message.position
#endregion
