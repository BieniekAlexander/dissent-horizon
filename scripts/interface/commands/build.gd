class_name Build
extends Command

var build_cells: Set = null

static func tool_applies_to(command_tool_name: String, entity_type: Entity.Type) -> bool:
	return command_tool_name in {
		Entity.Type.UNIT_TECHNICIAN: [
			"command_tool_outpost",
			"command_tool_dwelling",
			"command_tool_mine",
			"command_tool_lab",
			"command_tool_compound",
			"command_tool_armory",
		]
	}.get(entity_type, [])

static func meets_precondition(a_actor: Commandable, a_message: CommandMessage) -> PreconditionFailureCause:
	if a_message.tool==null:
		return PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
	elif not a_actor.commander.has_resources_for(a_message.tool.type):
		return PreconditionFailureCause.NOT_ENOUGH_RESOURCES
	elif not StructureSpec.structure_type_spec_map[a_message.tool.type].placement_checker.call(
		a_message,
		StructureSpec.structure_type_spec_map[a_message.tool.type].cube_grid_arrangement
	):
		return PreconditionFailureCause.INVALID_PLACEMENT
	else:
		return PreconditionFailureCause.NONE

func can_act(a_actor: Commandable) -> bool:
	# TODO update this check such that the position is centered with respect to the build location
	push_error("Fix up")
	return SU.linf_distance(VU.inXZ(a_actor.global_position), VU.inXZ(message.world_position))<1

func fulfill_action(a_actor: Commandable) -> Variant:
	push_error("Account for position")
	var new_structure: Commandable = message.tool.packed_scene.instantiate()
	
	new_structure.initialize(message.map, a_actor.commander)
	#message.map.add_structure(new_structure, hex_location, 0)
	message.map.add_entity(new_structure, message.xz_position, a_actor.commander)
	new_structure.build_progress = .1
	
	return Repair.new(CommandMessage.new(message.map, new_structure))

func should_move(a_actor: Commandable) -> bool:
	return a_actor.global_position.distance_squared_to(message.world_position) >= .25


### NODE
func _init(a_message: CommandMessage) -> void:
	super(a_message)
	build_cells = Commandable.get_arrangement_cells(
		a_message.map,
		VU.inXZ(a_message.position),
		StructureSpec.structure_type_spec_map[a_message.tool.type].cube_grid_arrangement
	)
