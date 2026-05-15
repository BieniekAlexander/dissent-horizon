class_name AttackMove
extends Command
### STATE UPDATES
func get_updated_state(a_actor: Commandable):
	var aggro_command: Command = a_actor.get_aggro_near_position(a_actor.global_position, a_actor.ATTACK_RANGE)
	return [aggro_command, self] if aggro_command!=null else self


## DEBUG
func _to_string() -> String:
	return "AttackMove: %s" % message.position
