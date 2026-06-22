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
	if repairable.build_progress >= 1:
		# Construction just completed; re-evaluate the tech tree so any structure
		# gated on this one (e.g. Mine requires Outpost) now unlocks.
		if repairable.commander != null:
			repairable.commander.proc_technology()
		if a_actor.veterancy != null:
			a_actor.veterancy.gain_experience(10)
		# If this actor landed to build (HOVERING builder in GROUNDED_TEMP), take off.
		if a_actor.movement != null and a_actor.movement.is_grounded_temp():
			a_actor.movement.take_off()
		return null
	return self
#endregion
