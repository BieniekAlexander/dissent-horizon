class_name Land
extends MoveCommand

#region Preconditions
## Fires immediately from the HUD — no target position required.
static func requires_position() -> bool:
	return false

## Valid only for HOVERING units that are not already permanently grounded
## (so the button grays out while the unit is already landed).
static func meets_precondition(
	actor: Commandable,
	_message: CommandMessage
) -> PreconditionFailureCause:
	if actor.aerial == null or actor.aerial.mode != Movement.Mode.HOVERING:
		return PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
	if actor.aerial.is_permanently_grounded():
		return PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
	return PreconditionFailureCause.NONE
#endregion

#region State updates
func should_move(_a_actor: Commandable) -> bool:
	return false

func can_act(_a_actor: Commandable) -> bool:
	return true

## Descend and remain grounded; a subsequent movement command lifts off.
func fulfill_action(a_actor: Commandable) -> Variant:
	a_actor.aerial.land_permanently()
	return null
#endregion

#region Debug
func _to_string() -> String:
	return "Land"
#endregion
