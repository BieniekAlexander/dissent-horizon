class_name Capture
extends MoveCommand

#region Preconditions
static func evaluator(a_actor: Commandable, a_message: CommandMessage) -> Variant:
	if meets_precondition(a_actor, a_message):
		return Capture
	else:
		return null

static func meets_precondition(
	a_actor: Commandable,
	a_message: CommandMessage
) -> PreconditionFailureCause:
	return (
		PreconditionFailureCause.NONE
		if a_message.target is Commandable and a_message.target.is_in_group("structure") and a_message.target.commander_id==0
		else PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
	)
#endregion

#region State updates
func can_act(a_actor: Commandable) -> bool:
	return SU.unit_is_close_to_structure(a_actor, message.target)

func fulfill_action(a_actor: Commandable) -> Variant:
	message.target.build_progress += .00222222222

	if message.target.build_progress<2:
		return self
	else:
		# Transferring ownership re-runs Commandable._on_commander_changed, which moves
		# the structure's vigor contribution from the old commander to the captor — so
		# the captor is credited (and the former owner debited) automatically here.
		message.target.commander = a_actor.commander
		return null


func should_move(a_actor: Commandable) -> bool:
	return not SU.unit_is_close_to_structure(a_actor, message.target)
#endregion
