class_name Land
extends Command

#region Preconditions
## Fires immediately from the HUD — no target position required.
static func requires_position() -> bool:
	return false

## Valid only for HOVERING units that are not already permanently grounded
## (so the button grays out while the unit is already landed).
static func meets_precondition(
	a_actor: Commandable,
	_a_message: CommandMessage
) -> PreconditionFailureCause:
	if a_actor.movement == null or a_actor.movement.mode != Movement.Mode.HOVERING:
		return PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
	if a_actor.movement.is_permanently_grounded():
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
	a_actor.movement.land_permanently()
	return null
#endregion

#region Debug
func _to_string() -> String:
	return "Land"
#endregion
