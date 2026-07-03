class_name AttackMove
extends MoveCommand

#region State updates
func get_updated_state(a_actor: Commandable) -> Variant:
	var aggro_command: MoveCommand = a_actor.get_aggro_near_position()
	# Return the aggro command directly (not wrapped in an array). The
	# update_commands(cmd, add_to_queue=true, prepend=true) path in
	# CommandReceiver already pushes the current AttackMove back to the front
	# of the queue, so wrapping self here would duplicate it.
	return aggro_command if aggro_command != null else self
#endregion

#region Debug
func _to_string() -> String:
	return "AttackMove: %s" % message.position
#endregion
