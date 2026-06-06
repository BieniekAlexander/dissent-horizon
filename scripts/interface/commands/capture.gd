class_name Capture
extends Command


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

func can_act(a_actor: Commandable) -> bool:
	return SU.unit_is_close_to_structure(a_actor, message.target)

func fulfill_action(a_actor: Commandable) -> Variant:
	message.target.build_progress += .00222222222
	
	if message.target.build_progress<2:
		return self
	else:
		message.target.commander = a_actor.commander
		# Capture transfers ownership and credits the captor with the captured
		# structure's population contribution. Read via the target's
		# ResourceProvider component rather than a Structure-class property.
		var provider: ResourceProvider = message.target.get_node_or_null("ResourceProvider") as ResourceProvider
		if provider != null:
			a_actor.commander.population_max += provider.population_provided
		return null
	

func should_move(a_actor: Commandable) -> bool:
	return not SU.unit_is_close_to_structure(a_actor, message.target)
