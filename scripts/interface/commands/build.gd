class_name Build
extends Command

#region Preconditions
static func tool_applies_to(command_tool_name: String, a_entity: Entity) -> bool:
	var builds := a_entity.get_node_or_null("Builds") as Builds
	if builds == null:
		return false
	var tool: Tool = Tool.command_tool_map.get(command_tool_name)
	if tool == null:
		return false
	return builds.can_build(tool.type)

static func meets_precondition(a_actor: Commandable, a_message: CommandMessage) -> PreconditionFailureCause:
	if a_message.tool==null:
		# Build is entered but the player hasn't chosen which structure to place
		# yet — a pending selection, not a failure.
		return PreconditionFailureCause.COMMAND_PENDING_TOOL
	var unmet: TechnologySpec.UnmetNeed = a_actor.commander.get_unmet_need(a_message.tool.type)
	if unmet != TechnologySpec.UnmetNeed.NONE:
		return unmet_need_to_precondition[unmet]
	var preview := a_actor.commander.get_build_preview_instance(a_message.tool)
	var obs := preview.get_node_or_null("Structure") as Structure if preview != null else null

	# A Mine is an OVERLAY structure: it binds to an existing Deposit instead of
	# occupying its own cells (see add_structure / _target_footprint, both keyed on
	# `is Mine`). The generic empty-cell Structure check can therefore never pass
	# for a mine — the deposit already occupies those cells — so a mine is gated on
	# the deposit check (OreExtractor.valid_placement) INSTEAD, not in addition.
	if preview is Mine:
		if not OreExtractor.valid_placement(a_message, obs.dimensions, obs.allow_uneven):
			return PreconditionFailureCause.INVALID_PLACEMENT
	elif not Structure.valid_placement(a_message, obs.dimensions, obs.allow_uneven):
		return PreconditionFailureCause.INVALID_PLACEMENT

	return PreconditionFailureCause.NONE
#endregion

#region Private helpers
## The grid cells the structure WILL occupy once placed, derived from the tool's
## footprint and the clicked spot via Map.footprint_cells — the exact same cells
## add_structure will register. The builder's "close enough" check measures against
## these, so being in range to place guarantees being in range to start building
## (Repair, which checks the registered footprint, then agrees by construction).
func _target_footprint(a_actor: Commandable) -> Array:
	var preview := a_actor.commander.get_build_preview_instance(message.tool)
	# An OVERLAY structure (a Mine) binds to an existing host (a Deposit) at the
	# clicked cell rather than occupying its own cells, so it never registers its
	# own footprint. Measure reach against the host's footprint so being in range to
	# place matches being in range to build (Repair resolves the same host footprint
	# via SU.structure_footprint once the overlay is bound).
	if preview is Mine:
		var cell := message.map.world_to_grid(message.xz_position)
		if message.map.grid_coordinates_in_bounds(cell):
			var host: Entity = message.map.cell_grid[cell.x][cell.y] as Entity
			if host != null:
				return message.map.structure_cell_map.get(host, [])
	var obs := preview.get_node_or_null("Structure") as Structure if preview != null else null
	var dims := obs.dimensions if obs != null else Vector2i.ONE
	return message.map.footprint_cells(message.xz_position, dims)
#endregion

#region Properties
## True once a landing sequence has been initiated for a HOVERING builder, so
## subsequent ticks while descending don't restart the landing or the build.
var _landing_started: bool = false
#endregion

#region State updates
func can_act(a_actor: Commandable) -> bool:
	return SU.unit_is_close_to_footprint(a_actor, message.map, _target_footprint(a_actor))

func fulfill_action(a_actor: Commandable) -> Variant:
	# HOVERING builders must land before placing the structure.  Start the
	# descent on the first call; subsequent calls while descending are no-ops
	# (land() is idempotent).  The actual placement happens in the callback.
	if a_actor.movement != null and a_actor.movement.mode == Movement.Mode.HOVERING \
			and not a_actor.movement.is_grounded_temp():
		if not _landing_started:
			_landing_started = true
			var msg: CommandMessage = message
			a_actor.movement.land(func() -> void:
				if not is_instance_valid(a_actor):
					return
				var new_structure: Commandable = msg.tool.packed_scene.instantiate()
				new_structure.build_progress = .1
				msg.map.add_entity(new_structure, msg.xz_position, a_actor.commander)
				a_actor.update_commands(
					Repair.new(CommandMessage.new(msg.map, new_structure))
				)
			)
		return self

	var new_structure: Commandable = message.tool.packed_scene.instantiate()
	# Mark as under construction before add_entity so that _ready → _on_commander_changed
	# → add_structure → proc_technology all see is_built = false. build_progress is not
	# @onready so this assignment survives _ready() without being overwritten.
	new_structure.build_progress = .1

	# Pass the raw clicked world XZ; add_entity → add_structure resolves the footprint
	# centre via Map.footprint_origin — the same logic the editor snap and the build
	# preview (Entity.valid_placement) use, so placement matches the preview.
	# add_entity calls initialize() itself, so we don't re-initialize here.
	message.map.add_entity(
		new_structure,
		message.xz_position,
		a_actor.commander
	)

	return Repair.new(CommandMessage.new(message.map, new_structure))

func should_move(a_actor: Commandable) -> bool:
	# Keep approaching until adjacent to the would-be footprint. Because the
	# footprint cells are the same ones Repair checks, the builder stops exactly
	# where it can both place AND continue building — no "placed but out of range".
	return not can_act(a_actor)
#endregion

#region Lifecycle
func _init(a_message: CommandMessage) -> void:
	super(a_message)
#endregion
