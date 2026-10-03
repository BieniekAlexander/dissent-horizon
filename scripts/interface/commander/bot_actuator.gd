class_name BotActuator
extends RefCounted

## BotActuator — the ONLY place the bot mutates game state.
##
## The strategy managers (military / production / economy) decide WHAT to do by
## reading the Bot's perception; they call into this thin layer to actually issue
## commands. Keeping all command construction here means the decision code stays
## pure and testable, and there's a single audited surface for "the bot did a
## thing". Mirrors the proven programmatic command paths (EventCommandPoint /
## EventIssueCommand): build a CommandMessage, wrap it in a Command, then
## update_commands + load_destination so the nav target is primed.

var _map: Map


func _init(a_map: Map) -> void:
	_map = a_map


## Order each unit to attack-move toward a world position. The destination is
## snapped to the navmesh first (a raw point off the mesh would be dropped).
## Attack-move makes units engage enemies encountered en route.
##
## `a_target_priority` is the WORST-ranked thing this attack-move's aggro will pick up, and
## it deliberately defaults WIDER than CommandMessage's own NON_COMBAT_UNITS default. An
## undefended enemy STRUCTURE ranks worse than that (Entity.TargetPriority.
## NON_COMBAT_STRUCTURES), so with the narrow default the bot's whole ATTACK posture could
## not raze anything: BotMilitary marches the army onto the nearest enemy structure,
## `AttackMove.get_updated_state` asks for aggro at NON_COMBAT_UNITS, the building the army
## is standing next to is ranked out, and every unit goes idle at the foot of the base.
##
## The player's attack-move is untouched — RTSController builds its own CommandMessage — so
## this widening is the bot's alone, and it is a DEFAULT rather than a hardcode: a caller
## that wants the army to walk past buildings passes the narrower rank.
func attack_move(
	a_units: Array,
	a_world_pos: Vector3,
	a_target_priority: Entity.TargetPriority = Entity.TargetPriority.NON_COMBAT_STRUCTURES
) -> void:
	if _map == null:
		return
	var dest: Vector3 = _map.nearest_navmesh_point(a_world_pos)
	for u: Commandable in a_units:
		var msg := CommandMessage.new(_map, null, null, dest)
		msg.target_priority = a_target_priority
		var cmd := AttackMove.new(msg)
		u.update_commands(cmd)
		# Prime the nav target: a fresh agent defaults target_position to (0,0,0),
		# so without this a destination at the map centre is silently dropped.
		u.load_destination(cmd)


## Order each unit to move to a world position WITHOUT engaging — a plain move
## command (not attack-move), so units don't aggro en route. Used to pull a kamikaze
## back to safety when no blast is worth it.
func move(a_units: Array, a_world_pos: Vector3) -> void:
	if _map == null:
		return
	var dest: Vector3 = _map.nearest_navmesh_point(a_world_pos)
	for u: Commandable in a_units:
		var cmd := MoveCommand.new(CommandMessage.new(_map, null, null, dest))
		u.update_commands(cmd)
		u.load_destination(cmd)


## Set where `a_structures` send what they produce: a plain move to a world position, which
## is exactly what a player's right-click with a producer selected sets (Commandable.set_rally).
## No unit is ordered here — Production hands the rally to each unit as it finishes it.
func rally(a_structures: Array, a_world_pos: Vector3) -> void:
	if _map == null:
		return
	var dest: Vector3 = _map.nearest_navmesh_point(a_world_pos)
	for s: Commandable in a_structures:
		s.set_rally(MoveCommand.new(CommandMessage.new(_map, null, null, dest)))


## Order each unit to attack a specific enemy entity directly. persist=false makes
## it a leashed engagement (drop the target if it flees / leaves range), so the unit
## returns to idle — and gets re-tasked — instead of chasing forever.
##
## A UNIT THAT CANNOT TOUCH THE TARGET IS SKIPPED, and this is the guard rather than a
## nicety. `Commandable.update_commands` does not consult preconditions — that is the
## player UI's job (`RTSController`) — so nothing downstream refuses an impossible Attack:
## `should_move` returns false (no weapon to close for), `can_act` returns false (nothing to
## fire), and `get_updated_state` returns `self` for a persistent one, which leaves the unit
## standing next to its target holding an order it can never finish or abandon. That is
## exactly the reported "several units had received a command to attack it … they sort of
## waited near their target until it had expired".
##
## The refusal is asked as `Attack.meets_precondition`, the same way `use_sanction` asks
## `UseSanction`'s, so the actuator can never issue an order the command itself calls
## impossible — and so the two definitions cannot drift apart. Deciding NOT to order this
## unit is the callers' job (BotKamikaze holds a drone with no worthwhile blast rather than
## letting it idle); this is the floor under them.
func attack(a_units: Array, a_target: Entity, a_persist: bool = true) -> void:
	if _map == null or a_target == null:
		return
	for u: Commandable in a_units:
		var msg := CommandMessage.new(_map, a_target)
		msg.persist = a_persist
		if Attack.meets_precondition(u, msg) != MoveCommand.PreconditionFailureCause.NONE:
			continue
		var cmd := Attack.new(msg)
		u.update_commands(cmd)
		u.load_destination(cmd)


## Order a builder to place a structure of `type` at a world position. For an Extractor
## (overlay), world_pos must sit on the target ExtractionSite's cell. Tech/resource/
## placement validity are enforced downstream by Build.meets_precondition, so an
## invalid request is a safe no-op (the builder just won't complete it).
func build(a_builder: Commandable, a_type: StringName, a_world_pos: Vector3) -> bool:
	var tool := Tool.for_type(a_type)
	if tool == null:
		return false
	var msg := CommandMessage.new(_map, null, tool, a_world_pos)
	# Register the purchase on the commander's production queue BEFORE constructing the
	# command, so the command registers as a holder of it (see MoveCommand._init) and the
	# cost is reserved / refunded with the order. Without this the builder would walk to
	# the site and wait forever, since nothing would ever fund the build.
	Build.submit_purchase(a_builder.commander, msg)
	var cmd := Build.new(msg)
	a_builder.update_commands(cmd)
	a_builder.load_destination(cmd)
	return true


## Order a unit to interact with a target (e.g. a Warlord liberating a Shelter). The
## unit paths to the target and performs its applicable Interaction on arrival. The
## message's `position` derives from the target, so load_destination primes the nav goal.
## Applicability (the unit owning a matching Interactor interaction, the target being
## available) is enforced downstream by Interact.meets_precondition, so an invalid
## request is a safe no-op.
func interact(a_unit: Commandable, a_target: Entity) -> void:
	if _map == null or a_target == null:
		return
	var cmd := Interact.new(CommandMessage.new(_map, a_target))
	a_unit.update_commands(cmd)
	a_unit.load_destination(cmd)


## Order [unit] to enter [host]'s garrison. The Occupy precondition enforces
## GROUNDED movement and a same-team or neutral, built Garrison host;
## precondition failures are silently handled by Occupy itself.
func garrison_into(a_unit: Commandable, a_host: Commandable) -> void:
	if _map == null:
		return
	var cmd := Occupy.new(CommandMessage.new(_map, a_host, null, a_host.global_position))
	a_unit.update_commands(cmd)
	a_unit.load_destination(cmd)


## Order `a_caster` to cast `a_sanction` at `a_world_pos` — the SAME route the player takes.
##
## The bot used to call `Sanction.activate` and `Abilities.spend` itself, which duplicated
## UseSanction.fulfill_action's body while skipping every gate in its precondition: whether
## the grid still has the sanction unlocked, whether this building is a caster for it,
## whether it is finished, whether it is POWERED, and whether the target is spotted. That is
## not just a missing check — it is a second implementation of the same action that could
## drift from the player's without any test noticing.
##
## The precondition is asked here rather than left downstream, exactly as RTSController asks
## it before issuing, so a refused cast holds the charge instead of ordering something the
## command will silently drop. Returns whether the order was issued.
##
## `a_world_pos` is ignored by a sanction that needs no target; no payload is chosen, so a
## sanction with cargo takes its default.
func use_sanction(a_caster: Commandable, a_sanction: Sanction, a_world_pos: Vector3) -> bool:
	if _map == null or a_caster == null or a_sanction == null:
		return false
	var msg := CommandMessage.new(_map, null, null, a_world_pos)
	msg.sanction = a_sanction
	if UseSanction.meets_precondition(a_caster, msg) != MoveCommand.PreconditionFailureCause.NONE:
		return false
	a_caster.update_commands(UseSanction.new(msg))
	return true


## Queue one unit of `type` at a production structure. Returns false only when no tool
## produces `type`. The purchase goes onto the commander's global production queue,
## which deducts the cost and hands the job to `structure` as soon as it's affordable —
## so a too-expensive request is banked, not dropped. Submitted straight to the queue
## rather than as a Train command so the structure stops reading as idle in the SAME
## tick (see Bot.get_idle_production_structures), which is what stops the bot
## re-ordering the unit it just ordered.
func train(a_structure: Commandable, a_type: StringName) -> bool:
	var tool := Tool.for_type(a_type)
	if tool == null or a_structure.commander == null:
		return false
	a_structure.commander.production_queue.submit_train(tool, [a_structure])
	return true
