class_name Build
extends Command


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
		# Build is entered but the player hasn't chosen which structure to place
		# yet — a pending selection, not a failure.
		return PreconditionFailureCause.COMMAND_PENDING_TOOL
	var unmet: TechnologySpec.UnmetNeed = a_actor.commander.get_unmet_need(a_message.tool.type)
	if unmet != TechnologySpec.UnmetNeed.NONE:
		return unmet_need_to_precondition[unmet]
	var preview := a_actor.commander.get_build_preview_instance(a_message.tool)
	var obs := preview.get_node_or_null("Obstruction") as Obstruction if preview != null else null
	var dims := obs.dimensions if obs != null else Vector2i.ONE
	if not StructureSpec.structure_type_spec_map[a_message.tool.type].placement_checker.call(
		a_message,
		dims
	):
		return PreconditionFailureCause.INVALID_PLACEMENT
	return PreconditionFailureCause.NONE

## World-space Chebyshev reach within which the builder is "close enough" to
## lay down and work on the structure. It grows with the building's footprint so
## a large structure (e.g. the 3x3 Outpost) doesn't require the builder to stand
## on a cell the building itself will occupy: half the larger extent (centre →
## edge) plus a one-cell working buffer.
func _build_reach(a_actor: Commandable) -> float:
	var preview := a_actor.commander.get_build_preview_instance(message.tool)
	var obs := preview.get_node_or_null("Obstruction") as Obstruction if preview != null else null
	var dims := obs.dimensions if obs != null else Vector2i.ONE
	return maxf(float(max(dims.x, dims.y)), 1.5)

func can_act(a_actor: Commandable) -> bool:
	return SU.linf_distance(VU.inXZ(a_actor.global_position), VU.inXZ(message.world_position)) < _build_reach(a_actor)

func fulfill_action(a_actor: Commandable) -> Variant:
	var new_structure: Commandable = message.tool.packed_scene.instantiate()

	# add_entity treats its location argument as GRID indices (Vector2i), so the
	# clicked world position must be converted first — passing the raw world XZ
	# truncates to a far-off cell. add_entity calls initialize() itself, so we
	# don't re-initialize here.
	message.map.add_entity(
		new_structure,
		message.map.world_to_grid(message.xz_position),
		a_actor.commander
	)
	new_structure.build_progress = .1

	return Repair.new(CommandMessage.new(message.map, new_structure))

func should_move(a_actor: Commandable) -> bool:
	# Stop approaching once inside the (size-aware) build reach, so the builder
	# parks just outside a large footprint rather than walking into its centre.
	var reach := _build_reach(a_actor)
	return a_actor.global_position.distance_squared_to(message.world_position) >= reach * reach


### NODE
func _init(a_message: CommandMessage) -> void:
	super(a_message)
