class_name Collect
extends Command

# NOTE: Hardcoding the specifics of the Tech Lab interaction, but generalize this

#region State updates
func should_move(a_actor: Commandable) -> bool:
	return !SU.unit_is_close_to_target(a_actor, message.target)

func can_act(a_actor: Commandable) -> bool:
	return SU.unit_is_close_to_target(a_actor, message.target, .01) \
		and message.target.build_up > 5

func fulfill_action(a_actor: Commandable) -> Variant:
	message.target.build_up = 0
	print("collected")
	return null
#endregion
