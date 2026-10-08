class_name AttackMove
extends MoveCommand


## Refused for a piece on rails (Actor.is_on_rails): it cannot go where it is sent. The
## button still serves it — clicked on a target, it resolves to Attack instead.
static func meets_precondition(
	actor: Actor, _message: CommandMessage
) -> PreconditionFailureCause:
	if actor != null and actor.is_on_rails():
		return PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
	return PreconditionFailureCause.NONE


## This order exists in order to shoot, so an empty charged loadout makes it undoable for
## now. The receiver stands it down into the queue rather than have the unit fly at
## something it cannot touch — it resumes once the unit has been back to an airfield.
func requires_ammo() -> bool:
	return true


func releases_hold_fire() -> bool:
	return true


#region State updates
func get_updated_state(a_actor: Actor) -> Variant:
	var aggro_command: MoveCommand = a_actor.get_aggro_near_position(
		null, null, message.target_priority
	)
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
