class_name Build
extends MoveCommand

## Safehouse conversion: the safehouse build tool aimed at a NEUTRAL building upgrades
## that building IN PLACE into a safehouse — the same node keeps its HP, footprint and
## garrison (with any occupants), but gains the converting commander's ownership, a
## safehouse's vigor, and the safehouse sprite. Cheaper/quicker than building one from
## scratch, and — unlike a Mine on a Deposit — it is a transition, not an overlay: there
## is no underlying building left to re-expose if the safehouse is later destroyed.
const SAFEHOUSE_CONVERSION_ORE: int = 50
const SAFEHOUSE_CONVERSION_SECONDS: float = 5.0

#region Preconditions
static func tool_applies_to(command_tool_name: String, a_entity: Entity) -> bool:
	var builds := a_entity.get_node_or_null("Builds") as Builds
	if builds == null:
		return false
	var tool: Tool = Tool.for_name(command_tool_name)
	if tool == null:
		return false
	return builds.can_build(tool.type)

## True when this Build is a safehouse conversion: the safehouse tool aimed at a
## still-neutral building. Restricted to NT_STRUCTURE_BUILDING owned by commander 0, so
## a building that's already owned (or garrisoned, which adopts a commander) isn't a
## conversion target.
static func _is_safehouse_conversion(a_message: CommandMessage) -> bool:
	if a_message.tool == null or a_message.tool.type != EntityIds.SAFEHOUSE:
		return false
	var target := a_message.target as Commandable
	return target != null and is_instance_valid(target) \
		and target.id == EntityIds.BUILDING \
		and target.commander_id == 0

static func meets_precondition(a_actor: Commandable, a_message: CommandMessage) -> PreconditionFailureCause:
	if a_message.tool==null:
		# Build is entered but the player hasn't chosen which structure to place
		# yet — a pending selection, not a failure.
		return PreconditionFailureCause.COMMAND_PENDING_TOOL

	# Safehouse-on-building: the safehouse tool aimed at a neutral building converts it
	# in place rather than placing a new structure, with its own (cheaper) cost and no
	# empty-cell placement check — analogous to how a Mine special-cases a Deposit below.
	if _is_safehouse_conversion(a_message):
		if a_actor.commander.ore < SAFEHOUSE_CONVERSION_ORE:
			return PreconditionFailureCause.NOT_ENOUGH_ORE
		return PreconditionFailureCause.NONE

	# Placement is checked BEFORE resources/tech: an invalid-placement result drives a
	# terrain visual cue, and letting a NOT_ENOUGH_ORE / MISSING_STRUCTURE result short-
	# circuit ahead of it would suppress that cue and confuse the player. So resolve
	# placement first, then fall through to the resource/tech gate.
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

	var unmet: TechnologySpec.UnmetNeed = a_actor.commander.get_unmet_need(a_message.tool.type)
	if unmet != TechnologySpec.UnmetNeed.NONE:
		return unmet_need_to_precondition[unmet]

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

## A structure already occupying this build's target footprint, or null. Typically the
## one a CO-BUILDER (another unit in the same multi-select Build) placed this very frame:
## every selected builder gets its own Build aimed at the same cells, and they may arrive
## together. Detecting the existing structure lets later arrivals co-build it instead of
## placing a duplicate (which TerrainGrid.place_building rejects with an assertion).
##
## Overlay structures (Mines) bind onto an already-occupied cell (their host Deposit) by
## design, so an occupied footprint is normal for them and never a conflict — skip them.
func _structure_on_target_footprint(a_actor: Commandable) -> Entity:
	if message.map == null or message.tool == null:
		return null
	var preview := a_actor.commander.get_build_preview_instance(message.tool)
	if preview is Mine:
		return null
	for cell: Vector2i in _target_footprint(a_actor):
		if message.map.grid_coordinates_in_bounds(cell):
			var occupant := message.map.cell_grid[cell.x][cell.y] as Entity
			if occupant != null:
				return occupant
	return null

## True when `occupant` is the structure THIS build is trying to place, already put down
## by a co-builder and still under construction — i.e. safe to join repairing rather than
## re-placing. Foreign, finished, or different-type occupants fail the check, so the
## builder aborts instead of double-placing.
func _is_our_cobuilt_structure(occupant: Entity, a_actor: Commandable) -> bool:
	if not (occupant is Commandable):
		return false
	var s := occupant as Commandable
	return not s.is_built \
		and s.commander == a_actor.commander \
		and message.tool != null and message.tool.packed_scene != null \
		and s.scene_file_path == message.tool.packed_scene.resource_path

## Runs the post-placement fixup. Invoked via call_deferred from
## fulfill_action: it MUST run after the command receiver has swapped this Build
## for the follow-up Repair. Running it inline (during fulfill_action) would
## prepend the displacement move while this Build is still the placing builder's
## active `_command`, which update_commands(prepend) pushes onto the queue — so
## the still-active Build re-executes next tick and places the structure a second
## time on the same cells (TerrainGrid.place_building then asserts "already
## occupied"). Deferring means the builder's active command is Repair by now, so
## displacing it simply queues that Repair behind the move (step out, then build).
##
## Displacement — any unit standing on the now-blocked cells (the placing builder
## included) gets a move command prepended so it exits the navmesh hole. The
## navmesh rebuild is itself deferred (NavManager uses call_deferred), so
## nearest_navmesh_point may still reflect the old mesh here; NavigationAgent3D
## re-snaps to the nearest valid point once the updated mesh syncs.
##
## Conflicting builds (other selected units aiming the same Build at these cells)
## need no handling here: each such builder's fulfill_action now detects the placed
## structure on arrival and joins repairing it (see _structure_on_target_footprint),
## so the whole selection co-builds ONE structure instead of double-placing.
func _after_placement(new_structure: Commandable, a_map: Map) -> void:
	if not is_instance_valid(new_structure) or a_map == null:
		return
	var placed_footprint: Array = a_map.structure_cell_map.get(new_structure, [])
	if placed_footprint.is_empty():
		return
	var cell_set: Dictionary = {}
	for cell: Vector2i in placed_footprint:
		cell_set[cell] = true

	# Prepend a move command to every unit standing inside the blocked footprint.
	for node in a_map.get_tree().get_nodes_in_group("commandable"):
		var unit: Commandable = node as Commandable
		if unit == null or not unit.is_in_group("unit") or unit.movement == null:
			continue
		var unit_cell: Vector2i = a_map.world_to_grid(VU.inXZ(unit.global_position))
		if cell_set.has(unit_cell):
			var nav_point: Vector3 = a_map.nearest_navmesh_point(unit.global_position)
			var move_msg: CommandMessage = CommandMessage.new(a_map, null, null, nav_point)
			unit.update_commands(MoveCommand.new(move_msg), true, true)
#endregion

#region Properties
## True once a landing sequence has been initiated for a HOVERING builder, so
## subsequent ticks while descending don't restart the landing or the build.
var _landing_started: bool = false

## Safehouse-conversion progress: seconds the builder has spent converting, and
## whether the one-time ore cost has been charged yet.
var _conversion_elapsed: float = 0.0
var _conversion_paid: bool = false
#endregion

#region State updates
## Building is a channeled action: a hit staggers the builder, pausing placement/build
## progress until the stagger wears off.
func blocked_by_stagger(_a_actor: Commandable) -> bool:
	return true

func can_act(a_actor: Commandable) -> bool:
	# A safehouse conversion works against the existing building's footprint, not a
	# would-be placement footprint.
	if _is_safehouse_conversion(message):
		return is_instance_valid(message.target) \
			and SU.unit_is_close_to_structure(a_actor, message.target)
	return SU.unit_is_close_to_footprint(a_actor, message.map, _target_footprint(a_actor))

func fulfill_action(a_actor: Commandable) -> Variant:
	# Safehouse conversion: spend the cost once, work for SAFEHOUSE_CONVERSION_SECONDS,
	# then transition the building in place. Handled before the placement logic below,
	# which doesn't apply (nothing new is built).
	if _is_safehouse_conversion(message):
		return _fulfill_conversion(a_actor)

	# Co-build guard: by the time this builder arrives the cells may already hold a
	# structure — typically one a co-builder (another unit in the same multi-select
	# Build) placed first. Placing a second on the same cells trips
	# TerrainGrid.place_building's "already occupied" assertion, so join repairing our
	# structure (co-build) if it's there, or abort if the spot is otherwise taken.
	var existing: Entity = _structure_on_target_footprint(a_actor)
	if existing != null:
		return Repair.new(CommandMessage.new(message.map, existing)) \
			if _is_our_cobuilt_structure(existing, a_actor) else null

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
				# Re-check: a co-builder may have placed it during the descent.
				var existing_now: Entity = _structure_on_target_footprint(a_actor)
				if existing_now != null:
					a_actor.update_commands(
						Repair.new(CommandMessage.new(msg.map, existing_now)) \
							if _is_our_cobuilt_structure(existing_now, a_actor) else null
					)
					return
				var new_structure: Commandable = msg.tool.packed_scene.instantiate()
				new_structure.begin_construction()
				a_actor.commander.use_resources_for(msg.tool.type)
				msg.map.add_entity(new_structure, msg.xz_position, a_actor.commander)
				a_actor.update_commands(
					Repair.new(CommandMessage.new(msg.map, new_structure))
				)
				# Deferred so it runs after update_commands settles the Repair as the
				# active command (see _after_placement).
				_after_placement.call_deferred(new_structure, msg.map)
			)
		return self

	var new_structure: Commandable = message.tool.packed_scene.instantiate()
	# Mark as under construction before add_entity so that _ready → _on_commander_changed
	# → add_structure → proc_technology all see is_built = false. begin_construction sets
	# build_progress (not @onready) so this survives _ready() without being overwritten.
	new_structure.begin_construction()
	a_actor.commander.use_resources_for(message.tool.type)

	# Pass the raw clicked world XZ; add_entity → add_structure resolves the footprint
	# centre via Map.footprint_origin — the same logic the editor snap and the build
	# preview (Entity.valid_placement) use, so placement matches the preview.
	# add_entity calls initialize() itself, so we don't re-initialize here.
	message.map.add_entity(
		new_structure,
		message.xz_position,
		a_actor.commander
	)
	# Deferred: this runs AFTER the command receiver swaps this Build for the
	# Repair we return below. See _after_placement for why that ordering matters.
	_after_placement.call_deferred(new_structure, message.map)

	return Repair.new(CommandMessage.new(message.map, new_structure))

func should_move(a_actor: Commandable) -> bool:
	# Keep approaching until adjacent to the would-be footprint. Because the
	# footprint cells are the same ones Repair checks, the builder stops exactly
	# where it can both place AND continue building — no "placed but out of range".
	return not can_act(a_actor)

## Tick the in-range safehouse conversion: charge the ore once, accumulate time, and
## transition the building once SAFEHOUSE_CONVERSION_SECONDS have elapsed. Returns self
## while still working, null when done (or the target is no longer a convertible
## building — e.g. another builder finished it first).
func _fulfill_conversion(a_actor: Commandable) -> Variant:
	if not _is_safehouse_conversion(message):
		return null
	if not _conversion_paid:
		if a_actor.commander.ore < SAFEHOUSE_CONVERSION_ORE:
			return null
		a_actor.commander.add_ore(-SAFEHOUSE_CONVERSION_ORE)
		_conversion_paid = true
	_conversion_elapsed += a_actor.get_physics_process_delta_time()
	if _conversion_elapsed < SAFEHOUSE_CONVERSION_SECONDS:
		return self
	_convert_building_to_safehouse(message.target as Commandable, a_actor.commander)
	return null

## Transition `building` in place into a safehouse owned by `commander`: it keeps its
## HP, footprint, garrison and any garrisoned occupants (same node), and gains the
## commander's ownership, a safehouse's vigor, the safehouse type, and the safehouse
## sprite. The structure_type_map entry is re-keyed BUILDING → SAFEHOUSE so the
## commander accounts for it as a safehouse.
func _convert_building_to_safehouse(building: Commandable, commander: Commander) -> void:
	if not is_instance_valid(building) or commander == null:
		return
	# Ownership transfer: reparents under the commander, tints it, re-registers it on
	# the grid, and (via _on_commander_changed) moves it off the neutral commander.
	building.commander = commander
	# Re-key the commander's structure map from the building type to the safehouse type.
	commander.remove_structure(building)
	building.id = EntityIds.SAFEHOUSE
	commander.add_structure(building)
	# Grant the safehouse's vigor capacity (the building provided none). Sourced from
	# the safehouse scene's own value so the two stay in sync.
	var preview := commander.get_build_preview_instance(message.tool) as Commandable
	var safehouse_vigor: int = preview.vigor_provided if preview != null else 50
	building.vigor_provided = safehouse_vigor
	commander.adjust_vigor(0, safehouse_vigor)
	# Swap to the safehouse sprite so it reads as a safehouse.
	var sprite := building.get_node_or_null("Sprite") as Sprite3D
	if sprite != null:
		sprite.texture = load("res://assets/entities/safehouse.png")
#endregion

#region Lifecycle
func _init(a_message: CommandMessage) -> void:
	super(a_message)
#endregion
