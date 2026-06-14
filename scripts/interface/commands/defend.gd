class_name Defend
extends Command

#region State updates
func should_move(a_actor: Commandable) -> bool:
	return (
		(VU.inXZ(a_actor.global_position)-VU.inXZ(message.position)).length_squared()
	) > .5

func get_updated_state(a_actor: Commandable):
	var new_command: Command = a_actor.get_aggro_near_position()
	return new_command if new_command != null else self

func fulfill_action(a_actor: Commandable) -> Variant:
	return self
#endregion
