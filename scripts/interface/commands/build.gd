class_name Build
extends MoveCommand

## Safehouse conversion: the safehouse build tool aimed at a NEUTRAL building upgrades
## that building IN PLACE into a safehouse — the same node keeps its HP, footprint and
## garrison (with any occupants), but gains the converting commander's ownership, a
## safehouse's infrastructure, and the safehouse sprite. Cheaper/quicker than building one from
## scratch, and — unlike an Extractor on a site — it is a transition, not an overlay: there
## is no underlying building left to re-expose if the safehouse is later destroyed.
const SAFEHOUSE_CONVERSION_ENERGY: int = 50
const SAFEHOUSE_CONVERSION_SECONDS: float = 5.0

#region Preconditions
static func tool_applies_to(command_tool_name: String, entity: Entity) -> bool:
	var builds := entity.get_node_or_null("Builds") as Builds
	if builds == null:
		return false
	var tool: Tool = Tool.for_name(command_tool_name)
	if tool == null:
		return false
	return builds.can_build(tool.type)

## The still-neutral building this Build would convert, or null when it isn't a
## conversion at all. Restricted to BUILDING owned by commander 0, so a building that's
## already owned (or garrisoned, which adopts a commander) isn't a conversion target.
##
## Resolved from the GRID — the structure the safehouse's own footprint would land
## squarely on top of (Map.concentric_structure) — rather than from whatever the cursor
## ray happened to hit. Two things follow, and both are the point:
##   * a conversion has ONE aim per building, the one that leaves the safehouse exactly
##     where the building stands, so there is no "close enough" that would place a
##     safehouse offset from the building it converts;
##   * what counts as aiming at a building is its FOOTPRINT, not the reach of its
##     selection collider, which is the same thing the placement check reads.
static func _conversion_target(commander: Commander, message: CommandMessage) -> Commandable:
	if commander == null or message == null or message.map == null:
		return null
	if message.tool == null or message.tool.type != EntityIds.AN_INFRASTRUCTURE:
		return null
	var host := message.map.concentric_structure(
		message.xz_position, _tool_dimensions(commander, message.tool)
	) as Commandable
	if host == null or not is_instance_valid(host):
		return null
	return host if host.id == EntityIds.NT_BUILDING and host.commander_id == 0 else null

## True when this Build is a safehouse conversion: the safehouse tool aimed squarely at a
## still-neutral building (see _conversion_target).
static func _is_safehouse_conversion(commander: Commander, message: CommandMessage) -> bool:
	return _conversion_target(commander, message) != null

## True when this build order will lay a NEW structure down at its target position — it
## has a chosen tool, and it isn't the safehouse conversion (which transitions a building
## that already stands there). Read by the HUD to decide whether the site deserves a
## blueprint ghost while the builder walks over.
static func places_new_structure(commander: Commander, message: CommandMessage) -> bool:
	return message != null and message.tool != null \
		and not _is_safehouse_conversion(commander, message)

static func meets_precondition(actor: Commandable, message: CommandMessage) -> PreconditionFailureCause:
	if message.tool==null:
		# Build is entered but the player hasn't chosen which structure to place
		# yet — a pending selection, not a failure.
		return PreconditionFailureCause.COMMAND_PENDING_TOOL

	# THIS ACTOR, not just any actor. The build sub-menu is offered to a MIXED selection as
	# soon as one member can build (CommandContextParser.tools_for_selection), so the order
	# reaches soldiers and trucks too — and without this they passed every remaining check
	# (placement, price, tech are all commander-wide) and were handed a Build they have no
	# Builds component to execute. RTSController.assign_command_to_units filters on this
	# precondition, so refusing here is what routes the order to the builders alone.
	if actor == null or not tool_applies_to(message.tool.command_name, actor):
		return PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE

	# Safehouse-on-building: the safehouse tool aimed at a neutral building converts it
	# in place rather than placing a new structure, with its own (cheaper) cost and no
	# empty-cell placement check — analogous to how an Extractor special-cases a site below.
	# With the additive modifier held an unaffordable conversion is queued rather than
	# refused, exactly like any other build. Outside it, the price is checked HERE against
	# the flat conversion cost rather than through get_blocking_need: this purchase is
	# priced ad-hoc (PurchaseTransaction.for_cost) and has no technology_mapping entry, so
	# asking the commander about the tool's listed type would gate on the wrong number.
	if _is_safehouse_conversion(actor.commander, message):
		if not message.defer_if_unaffordable \
				and actor.commander != null and actor.commander.energy < SAFEHOUSE_CONVERSION_ENERGY:
			return PreconditionFailureCause.NOT_ENOUGH_ENERGY
		return PreconditionFailureCause.NONE

	# Placement is checked BEFORE resources/tech: an invalid-placement result drives a
	# terrain visual cue, and letting a NOT_ENOUGH_ENERGY / MISSING_STRUCTURE result short-
	# circuit ahead of it would suppress that cue and confuse the player. So resolve
	# placement first, then fall through to the resource/tech gate.
	var preview := actor.commander.get_build_preview_instance(message.tool)
	var obs := preview.get_node_or_null("Structure") as Structure if preview != null else null

	# A Extractor is asked a DIFFERENT placement question, because it has two kinds of home. On
	# an ExtractionSite it is an OVERLAY: the site stays the cells' occupant and the extractor
	# binds to it (see Map.add_structure / _target_footprint), so the generic empty-cell check
	# can never pass — the site already occupies those cells. In a
	# lithium pond it occupies its cells like anything else. EnergyExtractor.valid_placement
	# is what knows which case applies; it is used INSTEAD of the generic check, not in
	# addition to it.
	if Extractor.of(preview) != null:
		if not EnergyExtractor.valid_placement(
			message, obs.dimensions, obs.allow_uneven, obs.allow_submerged
		):
			return PreconditionFailureCause.INVALID_PLACEMENT
	elif not Structure.valid_placement(
		message, obs.dimensions, obs.allow_uneven, obs.allow_submerged
	):
		return PreconditionFailureCause.INVALID_PLACEMENT

	# The cells can be geometrically legal and still be a bad idea: NavPlacement asks what
	# Structure.valid_placement does not — would this footprint split the walkable surface,
	# and, for a structure that trains units, does it still leave itself a side to put them
	# on. The bot has asked both since bot-economy's build-spot search; player placement
	# wants the same answers, so a wall-in the bot could never create should not be one the
	# player can either. gdd/systems/commands/construction.md §Placement keeps navigation intact.
	if not _placement_keeps_navmesh_access(message, preview, obs.dimensions):
		return PreconditionFailureCause.INVALID_PLACEMENT

	# A site this side already means to build on is taken, though nothing stands there yet: the
	# second plan is refused, not merged. Enemy plans are not ours to know about, so an enemy on
	# the site is found only when the builder arrives (see fulfill_action).
	var planned: Dictionary = actor.commander.planned_footprint_cells(message.planned_structure)
	if message.map.footprint_cells(message.xz_position, obs.dimensions).any(
			func(c: Vector2i) -> bool: return planned.has(c)):
		return PreconditionFailureCause.SITE_PLANNED

	# Tech prerequisites always refuse the order. A price the commander can't meet YET
	# refuses it too UNLESS the additive modifier is held (a_message.defer_if_unaffordable), in
	# which case the purchase is queued on the commander's ProductionQueue and the builder
	# waits at the site until it's funded (see fulfill_action). The flag defaults to true,
	# so scenario events and the bot are unaffected.
	var blocking: TechnologySpec.UnmetNeed = actor.commander.get_blocking_need(
		message.tool.type, message.defer_if_unaffordable
	)
	if blocking != TechnologySpec.UnmetNeed.NONE:
		return unmet_need_to_precondition[blocking]

	return PreconditionFailureCause.NONE

## The purchase that pays for the build `a_message` describes — the structure's listed
## cost, or the safehouse conversion's flat energy price. Submitted ONCE per order (not per
## builder) by whoever issues it, and stamped on the message so every builder in the
## order shares it.
static func submit_purchase(
	commander: Commander,
	message: CommandMessage
) -> PurchaseTransaction:
	if commander == null or message.tool == null:
		return null
	var transaction: PurchaseTransaction = (
		PurchaseTransaction.for_cost(
			commander, PurchaseTransaction.Kind.BUILD, message.tool, SAFEHOUSE_CONVERSION_ENERGY
		)
		if _is_safehouse_conversion(commander, message)
		else PurchaseTransaction.for_tool(
			commander, PurchaseTransaction.Kind.BUILD, message.tool
		)
	)
	message.transaction = transaction
	return commander.production_queue.submit(transaction)

## Raise the BLUEPRINT for the order `a_message` describes: an instance of the structure
## itself, in the PLANNED state (see Commandable.plan_construction), standing on the
## footprint the builders are walking to. Called ONCE per order, right after
## submit_purchase, and stamped on the message so every builder's snapshot shares the
## one blueprint (CommandMessage.deep_copy passes the reference through).
##
## Being a real entity — not a decorative ghost — is what lets the player select it and
## queue units at a building that hasn't been started yet. Its lifetime belongs to the
## purchase: placement consumes it, abandoning the order frees it (see
## PurchaseTransaction.discard_planned_structure).
##
## Returns null (and raises nothing) for a safehouse conversion, which transitions a
## building that already stands there, and for an order with no map/tool/commander.
static func plan_structure(
	commander: Commander,
	message: CommandMessage
) -> Commandable:
	if not places_new_structure(commander, message) or commander == null or message.map == null:
		return null
	if message.tool.packed_scene == null:
		return null
	var blueprint: Commandable = message.tool.packed_scene.instantiate() as Commandable
	if blueprint == null:
		return null
	# BEFORE initialize(): _ready and _on_commander_changed both read is_planned to skip
	# the line-of-sight, hp, infrastructure and registration a placed structure gets.
	blueprint.plan_construction()
	blueprint.initialize(message.map, commander)
	# Stand it where the structure will actually land — the same footprint centre
	# Map.add_structure will resolve when the builder commits it.
	var dims: Vector2i = _tool_dimensions(commander, message.tool)
	blueprint.global_position = message.map.footprint_centroid(
		message.map.footprint_origin(message.xz_position, dims), dims
	)
	message.planned_structure = blueprint
	if message.transaction != null:
		# Hand ownership of the node to the purchase, which frees it if the order is ever
		# abandoned. Defensive: should the purchase already have been settled (cancelled
		# during submit), take the blueprint straight back down rather than leaving one
		# standing with nothing to place it.
		message.transaction.planned_structure = blueprint
		if message.transaction.is_settled():
			message.transaction.discard_planned_structure()
			message.planned_structure = null
			return null
		# Seed the awaiting-funds shade from the purchase's CURRENT state, never from an
		# assumption that a fresh blueprint is unfunded. submit_purchase runs BEFORE this
		# (see RTSController.assign_command_to_units) and ProductionQueue.submit drains
		# synchronously, so an affordable build is already FUNDED by the time the blueprint
		# exists — and fund(), having fired before there was anything to notify, will never
		# fire again to clear a wrongly-set flag.
		blueprint.set_awaiting_funds(message.transaction.is_pending())
	return blueprint

## Footprint size of the structure `a_tool` places, read off the commander's cached
## preview instance (1×1 when the scene declares no Structure component).
static func _tool_dimensions(commander: Commander, tool: Tool) -> Vector2i:
	var preview: Node = commander.get_build_preview_instance(tool)
	var obs := preview.get_node_or_null("Structure") as Structure if preview != null else null
	return obs.dimensions if obs != null else Vector2i.ONE

## Whether laying `dimensions` down at `message`'s target keeps the map's navigation intact —
## NavPlacement's two rules (scripts/maps/nav_placement.gd), asked for every ordinary
## placement. Rule 1 (the footprint may not split the walkable surface) applies regardless of
## what is being built; rule 2 (a whole side left on walkable ground) is asked only of a
## structure with a Production component — `a_needs_access` narrowed to the case the reported
## bug actually was, a building units cannot leave. Rule 3 (the wide-unit class check) stays
## bot-only, as `bot-architecture.md` §Where a building goes already documents.
##
## True (no refusal) whenever there is no real map/grid to ask — an out-of-tree preview or a
## test fixture with no terrain — so this only ever narrows an ALREADY-VALID placement.
static func _placement_keeps_navmesh_access(
	message: CommandMessage, preview: Node, dimensions: Vector2i
) -> bool:
	if message.map == null or message.map.terrain_grid == null:
		return true
	var footprint: Array = message.map.footprint_cells(message.xz_position, dimensions)
	var needs_access: bool = preview != null and preview.get_node_or_null("Production") != null
	return NavPlacement.accepts(message.map.terrain_grid, footprint, needs_access)
#endregion

#region Purchase
## True when this build may go ahead: its purchase has been funded (the cost is already
## deducted and reserved), or it carries no purchase at all — the direct-issue path used
## by scenario events and tests, which pays inline at placement.
## Whether every structure this build requires is FINISHED. Asked at placement time rather
## than only at order time, because the additive modifier deliberately lets the order come
## first — see fulfill_action.
##
## Scoped to builds that went through the PURCHASE pipeline (`message.transaction`), the
## same distinction `_is_funded` draws: a directly-issued build — a scenario event, the
## bot's actuator, a test — never consulted the tech gate at order time either, and making
## it wait here would strand orders that used to place immediately. Only a player order can
## have been let through by the incoming-prerequisite deferral, so only a player order has
## anything to wait for.
func _prerequisites_met(a_actor: Commandable) -> bool:
	if message.transaction == null:
		return true
	if a_actor.commander == null or message.tool == null:
		return true
	var spec: TechnologySpec = a_actor.commander.technology_mapping.get(message.tool.type)
	if spec == null:
		return true
	return spec.required_structures.all(
		func(required: Variant) -> bool: return a_actor.commander.has_built_structure(required)
	)


func _is_funded() -> bool:
	return message.transaction == null or message.transaction.is_funded()

## Settle the cost at the moment the structure is actually laid down: spend the
## reservation the queue made, or — for a directly-issued build with no transaction —
## deduct inline, exactly as before.
func _pay(a_actor: Commandable) -> void:
	if message.transaction != null:
		message.transaction.consume()
	else:
		a_actor.commander.use_resources_for(message.tool.type)
#endregion

#region Private helpers
## The grid cells the structure WILL occupy once placed, derived from the tool's
## footprint and the clicked spot via Map.footprint_cells — the exact same cells
## add_structure will register. The builder's "close enough" check measures against
## these, so being in range to place guarantees being in range to start building
## (Assemble, which checks the registered footprint, then agrees by construction).
func _target_footprint(a_actor: Commandable) -> Array:
	# An OVERLAY structure (an Extractor) sits ON an existing host (an ExtractionSite), whose
	# footprint it takes as its own once placed. Measure reach against the host's footprint so
	# being in range to place matches being in range to build.
	var host: Entity = _target_host(a_actor)
	if host != null:
		return message.map.structure_cell_map.get(host, [])
	return message.map.footprint_cells(message.xz_position, _tool_dimensions(a_actor.commander, message.tool))

## For an OVERLAY build (an Extractor), the host it will bind onto — the ExtractionSite already
## standing on the target cells. Null for every ordinary build, which has no host.
## Resolved through the same concentric rule the placement check uses, so the host
## reached for is the one that made the placement legal.
func _target_host(a_actor: Commandable) -> Entity:
	if message.map == null or message.tool == null:
		return null
	if Extractor.of(a_actor.commander.get_build_preview_instance(message.tool)) == null:
		return null
	return message.map.concentric_structure(message.xz_position, _tool_dimensions(a_actor.commander, message.tool))

## Whether this build's lithium pond is already worked by somebody else's extractor.
##
## False for anything that is not an extractor, and for an extractor bound for an
## ExtractionSite rather than water — `water_body_under` answers null off water, and the site
## rule lives in EnergyExtractor.valid_placement.
func _target_pond_is_taken(a_actor: Commandable) -> bool:
	if message.map == null or message.tool == null or a_actor.commander == null:
		return false
	if Extractor.of(a_actor.commander.get_build_preview_instance(message.tool)) == null:
		return false
	var dimensions: Vector2i = _tool_dimensions(a_actor.commander, message.tool)
	var body: WaterBody = EnergyExtractor.water_body_under(
		message.map, message.xz_position, dimensions
	)
	return body != null and body.has_extractor()


## A structure already occupying this build's target footprint, or null. Typically the one a
## CO-BUILDER placed this very frame; detecting it lets later arrivals co-build rather than
## place a duplicate (which TerrainGrid.place_building rejects with an assertion).
##
## An OVERLAY structure (an Extractor on a site) is asked a DIFFERENT question — "is one of OURS
## already bound to that host", not "is anything on these cells" — because its target cells
## are legitimately occupied by the host it binds onto. Why, and what skipping extractors cost:
## CLAUDE.md §Command system.
func _structure_on_target_footprint(a_actor: Commandable) -> Entity:
	if message.map == null or message.tool == null:
		return null
	var host: Entity = _target_host(a_actor)
	if host != null:
		var site: ExtractionSite = ExtractionSite.of(host)
		return site.extractor if site != null else null
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
func _is_our_cobuilt_structure(a_occupant: Entity, a_actor: Commandable) -> bool:
	if not (a_occupant is Commandable):
		return false
	var s := a_occupant as Commandable
	return not s.is_built \
		and s.commander == a_actor.commander \
		and message.tool != null and message.tool.packed_scene != null \
		and s.scene_file_path == message.tool.packed_scene.resource_path

## Runs the post-placement fixup. Invoked via call_deferred from
## fulfill_action: it MUST run after the command receiver has swapped this Build
## for the follow-up Assemble. Running it inline (during fulfill_action) would
## prepend the displacement move while this Build is still the placing builder's
## active `_command`, which update_commands(prepend) pushes onto the queue — so
## the still-active Build re-executes next tick and places the structure a second
## time on the same cells (TerrainGrid.place_building then asserts "already
## occupied"). Deferring means the builder's active command is Assemble by now, so
## displacing it simply queues that Assemble behind the move (step out, then build).
##
## Displacement — any non-hostile unit standing on the now-blocked cells (the placing builder
## included; a hostile one would have ended the order) gets a move command prepended so it
## exits the navmesh hole. The navmesh rebuild is itself deferred (NavManager uses
## call_deferred), so nearest_navmesh_point may still reflect the old mesh here;
## NavigationAgent3D re-snaps to the nearest valid point once the updated mesh syncs.
##
## Conflicting builds (other selected units aiming the same Build at these cells)
## need no handling here: each such builder's fulfill_action now detects the placed
## structure on arrival and joins repairing it (see _structure_on_target_footprint),
## so the whole selection co-builds ONE structure instead of double-placing.
func _after_placement(a_new_structure: Commandable, a_map: Map) -> void:
	if not is_instance_valid(a_new_structure) or a_map == null:
		return
	var placed_footprint: Array = a_map.structure_cell_map.get(a_new_structure, [])
	if placed_footprint.is_empty():
		return
	var cell_set: Dictionary = {}
	for cell: Vector2i in placed_footprint:
		cell_set[cell] = true

	# Prepend a move command to every unit standing inside the blocked footprint.
	for node in a_map.get_tree().get_nodes_in_group("piece"):
		var unit: Commandable = node as Commandable
		if unit == null or not unit.is_in_group("unit") or not unit.can_move() \
				or unit.is_enemy_of(a_new_structure):
			continue
		var unit_cell: Vector2i = a_map.world_to_grid(VU.inXZ(unit.global_position))
		if cell_set.has(unit_cell):
			var nav_point: Vector3 = a_map.nearest_navmesh_point(unit.global_position)
			var move_msg: CommandMessage = CommandMessage.new(a_map, null, null, nav_point)
			unit.update_commands(MoveCommand.new(move_msg), true, true)
#endregion

#region Properties
## Safehouse-conversion progress: seconds the builder has spent converting, and
## whether the one-time energy cost has been charged yet.
var _conversion_elapsed: float = 0.0
var _conversion_paid: bool = false
#endregion

#region State updates
## ONE BUILDER ANSWERS A PLACEMENT. Five of them converging on one site is four builders not
## building anything else, and the co-build path (see Build.get_updated_state) exists for the
## case where the player genuinely wants several — by ordering them each in turn, not by one
## click meaning all of them.
##
## Build is not an [Ability] and is deliberately not being made into one; it simply shares
## the arity, which is a property of the ORDER rather than of the ability framing.
## `modifier_broaden` still puts the whole selection on it — see
## gdd/systems/ux/ui/control-matrices.md §Cast arity.
static func default_cast_arity(_message: CommandMessage) -> CastArity:
	return CastArity.SINGLE


## Building is a channeled action: a hit staggers the builder, pausing placement/build
## progress until the stagger wears off.
func blocked_by_stagger(_a_actor: Commandable) -> bool:
	return true

## Convert to Assemble as soon as our structure is standing, WITHOUT waiting to be in range.
##
## Every tick regardless of range, which is the whole point: a builder still walking to the
## site is stopped short by the very structure it is walking to, so `can_act` never becomes
## true and it can neither get in range to convert nor convert to get in range. Only the
## positive co-build case is handled here — an occupied-by-something-else footprint is still
## fulfill_action's call to abort, so this cannot turn a walk into a silent cancellation.
## The deadlock in full: CLAUDE.md §Command system.
func get_updated_state(a_actor: Commandable) -> Variant:
	if not _is_safehouse_conversion(a_actor.commander, message):
		var existing: Entity = _structure_on_target_footprint(a_actor)
		if existing != null and _is_our_cobuilt_structure(existing, a_actor):
			return Assemble.new(CommandMessage.new(message.map, existing))
	return super(a_actor)

func acting_action(_a_actor: Commandable) -> ActionTracker.Action:
	return ActionTracker.Action.BUILDING

func can_act(a_actor: Commandable) -> bool:
	# A safehouse conversion works against the existing building's footprint, not a
	# would-be placement footprint.
	var conversion: Commandable = _conversion_target(a_actor.commander, message)
	if conversion != null:
		return SU.unit_is_close_to_structure(a_actor, conversion)
	return SU.unit_is_close_to_footprint(a_actor, message.map, _target_footprint(a_actor))

func fulfill_action(a_actor: Commandable) -> Variant:
	# Safehouse conversion: spend the cost once, work for SAFEHOUSE_CONVERSION_SECONDS,
	# then transition the building in place. Handled before the placement logic below,
	# which doesn't apply (nothing new is built).
	if _is_safehouse_conversion(a_actor.commander, message):
		return _fulfill_conversion(a_actor)

	# Co-build guard: by the time this builder arrives the cells may already hold a
	# structure — typically one a co-builder (another unit in the same multi-select
	# Build) placed first. Placing a second on the same cells trips
	# TerrainGrid.place_building's "already occupied" assertion, so join repairing our
	# structure (co-build) if it's there, or abort if the spot is otherwise taken.
	var existing: Entity = _structure_on_target_footprint(a_actor)
	if existing != null:
		return Assemble.new(CommandMessage.new(message.map, existing)) \
			if _is_our_cobuilt_structure(existing, a_actor) else null

	# A RESERVOIR may have been claimed while this builder walked. The co-build guard above
	# only sees the target FOOTPRINT, and a pond is many cells wide — so a second extractor
	# aimed at a different part of the SAME body finds its own cells clear and would raise a
	# structure that splits one finite charge between two collectors. Abandon the order
	# instead; there is nothing here to co-build, because the other extractor is elsewhere.
	#
	# Re-asked HERE rather than trusted from order time because that is the whole gap: two
	# builders can be ordered at one pond before either has placed anything. The ExtractionSite
	# half of the same rule needs no equivalent — a site IS the footprint, so the guard above
	# already catches it.
	if _target_pond_is_taken(a_actor):
		return null

	# Nothing is laid down until the purchase is funded. An unaffordable build isn't
	# refused at order time any more — the builder walks to the site and WAITS here,
	# holding position, until the commander's ProductionQueue reserves its cost. Checked
	# ahead of the landing branch so a hovering builder waits in the air rather than
	# committing to a descent it can't yet pay off.
	if not _is_funded():
		return self

	# Nor until the PREREQUISITES are actually standing. The additive modifier lets a build be
	# ordered while its tech prerequisite is merely on its way (see
	# Commander.get_blocking_need), so the builder can arrive at the site before the
	# building that unlocks it exists. It waits here exactly as it waits for funding —
	# holding position — rather than the order being lost or the structure going up early.
	if not _prerequisites_met(a_actor):
		return self

	# HOVERING builders land first; land() is idempotent, and the tick after touchdown takes the
	# ordinary path below. Not a landing callback that swaps in the Assemble: update_commands
	# would clear the builds queued behind this one and take off again (it lifts a grounded unit
	# for any moving order). Returning it, as a ground builder does, replaces this command alone.
	if a_actor.aerial != null and a_actor.aerial.mode == Movement.Mode.HOVERING \
			and not a_actor.aerial.is_grounded_temp():
		a_actor.aerial.land(Callable())
		return self

	# An enemy standing on the site ends the order: the ground is contested, and the plan was
	# made without knowing it. A friendly one steps aside after placement (_after_placement).
	if _enemy_on_footprint(a_actor):
		return null

	var new_structure: Commandable = _place_structure(a_actor)
	# Deferred: this runs AFTER the command receiver swaps this Build for the
	# Assemble we return below. See _after_placement for why that ordering matters.
	_after_placement.call_deferred(new_structure, message.map)

	return Assemble.new(CommandMessage.new(message.map, new_structure))

## Whether a unit hostile to `a_actor` stands on this build's footprint — on the ground there,
## not held inside something and not flying over.
func _enemy_on_footprint(a_actor: Commandable) -> bool:
	var cells: Dictionary = {}
	for cell: Vector2i in _target_footprint(a_actor):
		cells[cell] = true
	for node: Node in a_actor.get_tree().get_nodes_in_group("unit"):
		var unit := node as Commandable
		# Airborne enemies overfly the site rather than stand on it.
		if unit != null and a_actor.is_enemy_of(unit) and not unit.is_garrisoned() \
				and not unit.is_airborne() \
				and cells.has(message.map.world_to_grid(VU.inXZ(unit.global_position))):
			return true
	return false

## Lay the structure down at the target site and return it.
##
## The normal (HUD-issued) path COMMITS the order's blueprint in place: the very node the
## player has been looking at since they clicked — and may already have queued units at —
## becomes the real building, so nothing about it is rebuilt or re-selected at placement.
## A build with no blueprint (scenario events, tests, the bot's direct orders)
## instantiates its structure here as before.
##
## Pays first either way: consuming the purchase releases its claim on the blueprint, so
## a later cancel can't free a building that now exists.
func _place_structure(a_actor: Commandable) -> Commandable:
	var blueprint: Commandable = message.planned_structure
	if blueprint != null and is_instance_valid(blueprint) and blueprint.is_planned:
		_pay(a_actor)
		blueprint.commit_construction(message.map, message.xz_position)
		_report_fulfilment(blueprint)
		return blueprint

	var new_structure: Commandable = message.tool.packed_scene.instantiate()
	# Mark as under construction before add_entity so that _ready → _on_commander_changed
	# → add_structure → proc_technology all see is_built = false. begin_construction sets
	# build_progress (not @onready) so this survives _ready() without being overwritten.
	new_structure.begin_construction()
	_pay(a_actor)

	# Pass the raw clicked world XZ; add_entity → add_structure resolves the footprint
	# centre via Map.footprint_origin — the same logic the editor snap and the build
	# preview (Entity.valid_placement) use, so placement matches the preview.
	# add_entity calls initialize() itself, so we don't re-initialize here.
	message.map.add_entity(
		new_structure,
		message.xz_position,
		a_actor.commander
	)
	_report_fulfilment(new_structure)
	return new_structure

## The BUILD half of the single fulfilment choke point: "the structure this purchase
## bought now stands here". The TRAIN half is Production._spawn_unit. Nothing listens
## today; the event exists so anything that later depends on this purchase is told at the
## moment the thing exists, rather than inferring it from the transaction disappearing.
func _report_fulfilment(a_structure: Commandable) -> void:
	if message.transaction != null:
		message.transaction.complete(a_structure)

## A build aimed ON TOP OF an obstruction — the safehouse conversion of a neutral building —
## walks to the host's nearest approach cell, because the site centre is inside the host and
## no builder can stand there. Every other build, an extractor on its walkable site included,
## is left to the default resolution (message.position, the site centre).
##
## Same cell Assemble reaches for (CommandReceiver._resolve_movement_target routes a
## structure-targeted command through SU.nearest_footprint_adjacent_cell), so placing and
## then building happen from one spot. Null when nothing adjacent is passable — the order
## then keeps the default rather than being silently dropped.
func movement_destination(a_actor: Commandable) -> Variant:
	var host: Entity = _obstructing_host(a_actor)
	if host == null:
		return null
	var nav_class: int = a_actor.movement.nav_agent_class if a_actor.movement != null \
			else SU.NO_NAV_CLASS
	var cell: Vector2i = SU.nearest_footprint_adjacent_cell(
		a_actor.global_position, host, message.map, nav_class
	)
	if cell == Vector2i(-1, -1):
		return null
	return message.map.grid_to_world(cell)

## The structure standing concentric with this build's footprint, if it blocks movement; null
## when the target is open ground or a walkable fixture such as an extraction site.
func _obstructing_host(a_actor: Commandable) -> Entity:
	if message.map == null or message.tool == null:
		return null
	var host: Entity = message.map.concentric_structure(
		message.xz_position, _tool_dimensions(a_actor.commander, message.tool)
	)
	return host if host != null and host.is_grid_obstruction() else null

func should_move(a_actor: Commandable) -> bool:
	# Keep approaching until adjacent to the would-be footprint. Because the
	# footprint cells are the same ones Assemble checks, the builder stops exactly
	# where it can both place AND continue building — no "placed but out of range".
	return not can_act(a_actor)

## A build is not finished by arriving at the site — `can_act` (footprint adjacency)
## decides that. Especially true here because the point a builder walks toward is the
## site CENTRE, which stops being reachable the moment a co-builder places the structure
## there: the agent then reports the path finished while the builder is still short of
## range, and ending the command on that would silently discard the build order.
func ends_on_arrival() -> bool:
	return false

## Tick the in-range safehouse conversion: charge the energy once, accumulate time, and
## transition the building once SAFEHOUSE_CONVERSION_SECONDS have elapsed. Returns self
## while still working, null when done (or the target is no longer a convertible
## building — e.g. another builder finished it first).
func _fulfill_conversion(a_actor: Commandable) -> Variant:
	var target: Commandable = _conversion_target(a_actor.commander, message)
	if target == null:
		return null
	if not _conversion_paid:
		# Same rule as a placement: wait at the building until the purchase is funded
		# rather than abandoning the order because the energy isn't in yet.
		if not _is_funded():
			return self
		if message.transaction != null:
			message.transaction.consume()
		elif a_actor.commander.energy < SAFEHOUSE_CONVERSION_ENERGY:
			return null
		else:
			a_actor.commander.add_energy(-SAFEHOUSE_CONVERSION_ENERGY)
		_conversion_paid = true
	_conversion_elapsed += a_actor.get_physics_process_delta_time()
	if _conversion_elapsed < SAFEHOUSE_CONVERSION_SECONDS:
		return self
	_convert_building_to_safehouse(target, a_actor.commander)
	return null

## Transition `building` in place into a safehouse owned by `commander`: it keeps its
## HP, footprint, garrison and any garrisoned occupants (same node), and gains the
## commander's ownership, a safehouse's infrastructure, the safehouse type, and the safehouse
## sprite. The structure_type_map entry is re-keyed BUILDING → SAFEHOUSE so the
## commander accounts for it as a safehouse.
func _convert_building_to_safehouse(a_building: Commandable, a_commander: Commander) -> void:
	if not is_instance_valid(a_building) or a_commander == null:
		return
	# Ownership transfer: reparents under the commander, tints it, re-registers it on
	# the grid, and (via _on_commander_changed) moves it off the neutral commander.
	a_building.commander = a_commander
	# Re-key the commander's structure map from the building type to the safehouse type.
	a_commander.remove_structure(a_building)
	a_building.id = EntityIds.AN_INFRASTRUCTURE
	a_commander.add_structure(a_building)
	# Grant the safehouse's infrastructure capacity (the building provided none). Sourced from
	# the safehouse scene's own value so the two stay in sync.
	var preview := a_commander.get_build_preview_instance(message.tool) as Commandable
	var safehouse_infrastructure: int = preview.infrastructure if preview != null else 50
	a_building.infrastructure = safehouse_infrastructure
	a_commander.add_infrastructure(safehouse_infrastructure)
	# Swap to the safehouse sprite so it reads as a safehouse.
	var sprite := a_building.get_node_or_null("Sprite") as Sprite3D
	if sprite != null:
		sprite.texture = load("res://assets/entities/safehouse.png")
#endregion

#region Lifecycle
func _init(a_message: CommandMessage) -> void:
	super(a_message)
#endregion
