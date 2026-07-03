class_name Stop
extends MoveCommand

#region Preconditions
static func requires_position() -> bool:
	return false
#endregion

#region State updates
func should_move(a_commandable: Commandable) -> bool:
	return false

func can_act(a_actor: Commandable) -> bool:
	return true

func fulfill_action(a_commandable: Commandable) -> Variant:
	return null
#endregion

#region Debug
func _to_string() -> String:
	return "Stop: %s" % message.position
#endregion
