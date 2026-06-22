class_name Evacuate
extends Command

#region Preconditions
## Fires immediately from the HUD — no target position required.
static func requires_position() -> bool:
	return false

## Valid when the issuing commandable owns a Garrison.
static func meets_precondition(
	a_actor: Commandable,
	a_message: CommandMessage
) -> PreconditionFailureCause:
	if not a_actor.has_node("Garrison"):
		return PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
	return PreconditionFailureCause.NONE
#endregion

#region State updates
## Structures don't move.
func should_move(_a_actor: Commandable) -> bool:
	return false

## Evacuate fires once the host is on the ground.
## For HOVERING hosts, land() is called each tick (idempotent) until
## GROUNDED_TEMP; evacuate() already calls take_off() at completion.
func can_act(a_actor: Commandable) -> bool:
	if a_actor.movement != null \
			and a_actor.movement.mode == Movement.Mode.HOVERING \
			and not a_actor.movement.is_grounded_temp():
		a_actor.movement.land(Callable())
		return false
	return true

## Restore all garrisoned units to the scene tree and disperse them.
func fulfill_action(a_actor: Commandable) -> Variant:
	var garrison := a_actor.get_node_or_null("Garrison") as Garrison
	if garrison != null:
		garrison.evacuate(message.map)
	return null
#endregion

#region Debug
func _to_string() -> String:
	return "Evacuate"
#endregion
