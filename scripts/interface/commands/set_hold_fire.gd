class_name SetHoldFire
extends MoveCommand

## A hold fire issued with the additive modifier: it waits in the actor's queue and, when the
## queue reaches it, sets the flag to what the toggle meant when it was pressed, then ends.
## Plain hold fire is no command at all — it flips the flag at once and leaves the queue alone
## (OrderDispatcher.toggle_hold_fire). gdd/design-framework/commitment-and-movement.md
## §Action timing.

## What the toggle set when it was pressed: hold (true) or release (false).
var is_holding: bool = true


func _init(a_message: CommandMessage, a_is_holding: bool = true) -> void:
	super(a_message)
	is_holding = a_is_holding


static func requires_position() -> bool:
	return false


func should_move(_a_actor: Commandable) -> bool:
	return false


func can_act(_a_actor: Commandable) -> bool:
	return true


func fulfill_action(a_actor: Commandable) -> Variant:
	a_actor.is_holding_fire = is_holding
	return null


func _to_string() -> String:
	return "SetHoldFire: %s" % ("hold" if is_holding else "release")
