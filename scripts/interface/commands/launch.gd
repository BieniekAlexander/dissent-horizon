class_name Launch
extends Command

static func meets_precondition(a_actor: Commandable, a_message: CommandMessage) -> PreconditionFailureCause:
	return PreconditionFailureCause.NONE
	if a_message.tool==null:
		return PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
	var unmet: TechnologySpec.UnmetNeed = a_actor.commander.get_unmet_need(a_message.tool.type)
	if unmet != TechnologySpec.UnmetNeed.NONE:
		return unmet_need_to_precondition[unmet]
	if not StructureSpec.structure_type_spec_map[a_message.tool.type].placement_checker.call(
		a_message,
		StructureSpec.structure_type_spec_map[a_message.tool.type].cube_grid_arrangement
	):
		return PreconditionFailureCause.INVALID_PLACEMENT
	return PreconditionFailureCause.NONE

func can_act(a_actor: Commandable) -> bool:
	return (a_actor.xz_position-message.xz_position).length_squared()<10.*10.

func fulfill_action(a_actor: Commandable) -> Variant:
	var projectile: HitBox = preload("res://scenes/projectiles/radiation.tscn").instantiate()
	message.map.add_entity(projectile, message.xz_position, a_actor.commander)
	return null

func should_move(a_actor: Commandable) -> bool:
	return not can_act(a_actor)
