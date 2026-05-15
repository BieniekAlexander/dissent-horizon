class_name Defend
extends Command


var range: float = 15.

### STATE UPDATES
func should_move(a_actor: Commandable) -> bool:
	return (
		(VU.inXZ(a_actor.global_position)-VU.inXZ(message.position)).length_squared()
	) > pow(range , 2)

func get_updated_state(a_actor: Commandable):
	var new_command: Command = a_actor.get_aggro_near_position(message.position, range)
	return [new_command, self] if new_command!=null else self

func fulfill_action(a_actor: Commandable) -> Variant:
	return self
