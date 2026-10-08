class_name Stop
extends MoveCommand


#region Preconditions
static func requires_position() -> bool:
	return false


#endregion


#region State updates
func should_move(_a_commandable: Actor) -> bool:
	return false


func can_act(_a_actor: Actor) -> bool:
	return true


func fulfill_action(_a_commandable: Actor) -> Variant:
	return null


#endregion


#region Debug
func _to_string() -> String:
	return "Stop: %s" % message.position
#endregion
