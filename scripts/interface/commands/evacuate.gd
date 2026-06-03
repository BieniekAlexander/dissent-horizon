class_name Evacuate
extends Command

## PRECONDITIONS

## Fires immediately from the HUD — no target position required.
static func requires_position() -> bool:
	return false

## Valid when the issuing commandable owns a Shelter.
static func meets_precondition(
	a_actor: Commandable,
	a_message: CommandMessage
) -> PreconditionFailureCause:
	if not a_actor.has_node("Shelter"):
		return PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
	return PreconditionFailureCause.NONE


## STATE UPDATES

## Structures don't move.
func should_move(_a_actor: Commandable) -> bool:
	return false

## Evacuate fires on the next tick after being issued.
func can_act(_a_actor: Commandable) -> bool:
	return true

## Restore all garrisoned units to the scene tree and disperse them.
func fulfill_action(a_actor: Commandable) -> Variant:
	var shelter := a_actor.get_node_or_null("Shelter") as Shelter
	if shelter != null:
		shelter.evacuate(message.map)
	return null


## DEBUG
func _to_string() -> String:
	return "Evacuate"
