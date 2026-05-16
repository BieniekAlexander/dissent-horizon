class_name Attack
extends Command


## COMMAND PRECONDITIONS
static func requires_position() -> bool:
	return true

static func meets_precondition(
	a_actor: Commandable,
	a_message: CommandMessage
) -> PreconditionFailureCause:
	return (
		PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
		if not _target_attackable(a_message)
		else PreconditionFailureCause.NONE
	)
	


### UTILS
static func _target_attackable(a_message: CommandMessage) -> bool:
	# TODO make it possible for units to attack the floor - unfortunately,
	# I previously wrote this such that a_message.target==null => the floor should be attacked,
	# but a_message.target becomes nul when a target dies, so checking it in that manner
	# causes this to always return true, even if the target used to be an object,
	# causing downstream checks to crash
	return is_instance_valid(a_message.target)
 

### STATE UPDATES
func get_updated_state(a_actor: Commandable):
	## Potentially return a new command based on a state check
	return null if not is_instance_valid(message.target) else self

func should_move(a_actor: Commandable) -> bool:
	return not (_target_attackable(message) and SU.is_in_attack_range(a_actor, message.target))

func can_act(a_actor: Commandable) -> bool:
	return (
		a_actor.attack_timer<=0
		and _target_attackable(message)
		and message.target!=a_actor
		and SU.is_in_attack_range(a_actor, message.target)
	)

func fulfill_action(a_actor: Commandable) -> Variant:
	## Perform the command's action and return any relevant follow-up commands
	a_actor.attack_timer = a_actor.ATTACK_DURATION
	var weapon: Weapon = Pattern.eval(a_actor.get_weapon_evaluation_patterns(), message.target)
	weapon.fire(a_actor, message.target)
	return self


## DEBUG
func _to_string() -> String:
	return "Attack: %s" % message.position
