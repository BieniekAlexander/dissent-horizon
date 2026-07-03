class_name Defend
extends MoveCommand

#region State updates
func can_act(a_actor: Commandable) -> bool:
	return (VU.inXZ(a_actor.global_position) - VU.inXZ(message.position)).length_squared() <= .5

func should_move(a_actor: Commandable) -> bool:
	return (VU.inXZ(a_actor.global_position) - VU.inXZ(message.position)).length_squared() > .5

func get_updated_state(a_actor: Commandable) -> Variant:
	var a_center: Variant = message.target if message.target != null else message.position
	var new_command: MoveCommand = a_actor.get_aggro_near_position(a_center, message.aggro_shape)
	if new_command != null and message.aggro_shape != null:
		new_command.message.aggro_shape = message.aggro_shape
	return new_command if new_command != null else self

func fulfill_action(a_actor: Commandable) -> Variant:
	return self
#endregion
