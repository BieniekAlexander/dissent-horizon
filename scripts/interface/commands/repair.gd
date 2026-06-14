class_name Repair
extends Command

#region Preconditions
static func meets_precondition(
	a_actor: Commandable,
	a_message: CommandMessage
) -> Command.PreconditionFailureCause:
	return PreconditionFailureCause.NONE
#endregion

#region State updates
func can_act(a_actor: Commandable) -> bool:
	return SU.unit_is_close_to_target(a_actor, message.target)

func fulfill_action(a_actor: Commandable) -> Variant:
	var repairable: Commandable = message.target # TODO might be repairing osmething other than a structure
	repairable.build_progress += .01 # TODO build rate
	return null if repairable.build_progress >= 1 else self
#endregion
