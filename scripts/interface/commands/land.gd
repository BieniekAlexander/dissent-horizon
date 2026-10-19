class_name Land
extends MoveCommand


#region Preconditions
## Fires immediately from the HUD — no target position required.
static func requires_position() -> bool:
	return false


## Valid only for HOVERING units not already coming down (so the button grays out while the
## unit is descending or landed — and comes back if a landing never got under way).
static func meets_precondition(actor: Actor, _message: CommandMessage) -> PreconditionFailureCause:
	if actor.aerial == null or actor.aerial.mode != Movement.Mode.HOVERING:
		return PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
	if actor.aerial.is_down_or_descending():
		return PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
	return PreconditionFailureCause.NONE


#endregion


## A Land sets down where the unit is: the move queued before it brakes to its goal, rather
## than passing through it at speed (CommandReceiver._arrival_for).
func continues_movement() -> bool:
	return false


#region State updates
func should_move(_a_actor: Actor) -> bool:
	return false


func can_act(_a_actor: Actor) -> bool:
	return true


## Descend and remain grounded; a subsequent movement command lifts off.
func fulfill_action(a_actor: Actor) -> Variant:
	a_actor.aerial.land_permanently()
	return null


#endregion


#region Debug
func _to_string() -> String:
	return "Land"
#endregion
