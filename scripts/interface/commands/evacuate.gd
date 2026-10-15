class_name Evacuate
extends MoveCommand


#region Preconditions
## Fires immediately from the HUD — no target position required.
static func requires_position() -> bool:
	return false


## Turning the garrison out is an ASIDE, not a change of plan: a transport carrying a route
## should drop its squad and then carry on along it. So this takes over now and whatever was
## running goes back to the front of the queue — see MoveCommand.is_interrupt.
static func is_interrupt() -> bool:
	return true


## Valid when the issuing commandable owns a Garrison that units may leave by order
## (Garrison.can_release). That is the EXIT question and is deliberately not is_closed(),
## which is about entry. Only the host's own side leaves by order; captives stay
## (Garrison.can_release_occupant).
static func meets_precondition(
	actor: Actor, _message: CommandMessage
) -> PreconditionFailureCause:
	var garrison := actor.get_node_or_null("Garrison") as Garrison
	if garrison == null or not garrison.can_release():
		return PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
	return PreconditionFailureCause.NONE


#endregion


#region State updates
## Structures don't move.
func should_move(_a_actor: Actor) -> bool:
	return false


## Whether a HOVERING host was still in the air when this tick's apply_state looked.
var _is_landing: bool = false


## For HOVERING hosts, land() is called each tick (idempotent) until GROUNDED_TEMP;
## evacuate() already calls take_off() at completion.
func apply_state(a_actor: Actor) -> void:
	_is_landing = (
		a_actor.aerial != null
		and a_actor.aerial.mode == Movement.Mode.HOVERING
		and not a_actor.aerial.is_grounded_temp()
	)
	if _is_landing:
		a_actor.aerial.land(Callable())


## Evacuate fires once the host is on the ground.
func can_act(_a_actor: Actor) -> bool:
	return not _is_landing


## Restore every occupant an order may release to the scene tree and disperse them. A
## captive stays where it is (Garrison.can_release_occupant).
func fulfill_action(a_actor: Actor) -> Variant:
	var garrison := a_actor.get_node_or_null("Garrison") as Garrison
	if garrison != null:
		garrison.evacuate_by_order(message.map)
	return null


#endregion


#region Debug
func _to_string() -> String:
	return "Evacuate"
#endregion
