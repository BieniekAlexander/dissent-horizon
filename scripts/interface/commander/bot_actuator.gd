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

## The one refusal the actuator raises itself: a type no tool produces is not a command's to
## refuse, since no command can be built for it.
const REFUSED_NO_TOOL: String = BotUsageLog.OUTCOME_REFUSED_PREFIX + "NO_TOOL"

var _map: Map

## Every order this actuator issues or refuses, counted per piece — read out by the self-play
## harness for the piece-usage audit; never read by a decision. See BotUsageLog.
var usage: BotUsageLog = BotUsageLog.new()


func _init(a_map: Map) -> void:
	_map = a_map


## EVERY VERB ASKS ITS COMMAND'S OWN PRECONDITION HERE, the way RTSController asks it before
## the player's click is issued, and records the answer under `a_kind` for `a_piece`. True
## when the order may be issued.
##
## One helper rather than a check per verb, because the verbs that did not ask (interact,
## garrison_into — "handled downstream by the command itself") were blind in the piece-usage
## audit: an order the command silently dropped was counted as ISSUED, so a piece the bot
## could never actually use read as used. The ledger is only honest if a refusal is counted
## where it is decided, and the command's static precondition is the one definition of
## "possible" that cannot drift from the player's.
func _admits(
	a_command_class: Script,
	a_actor: Actor,
	a_message: CommandMessage,
	a_kind: String,
	a_piece: StringName
) -> bool:
	var cause: MoveCommand.PreconditionFailureCause = a_command_class.meets_precondition(
		a_actor, a_message
	)
	if cause != MoveCommand.PreconditionFailureCause.NONE:
		usage.record_action(a_kind, a_piece, BotUsageLog.refused(cause))
		return false
	usage.record_action(a_kind, a_piece, BotUsageLog.OUTCOME_ISSUED)
	return true


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
	for u: Actor in a_units:
		var msg := CommandMessage.new(_map, null, null, dest)
		msg.target_priority = a_target_priority
		if not _admits(AttackMove, u, msg, "attack_move", u.id):
			continue
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
	for u: Actor in a_units:
		var msg := CommandMessage.new(_map, null, null, dest)
		if not _admits(MoveCommand, u, msg, "move", u.id):
			continue
		var cmd := MoveCommand.new(msg)
		u.update_commands(cmd)
		u.load_destination(cmd)


## Order each unit to move AT a piece — the controls' own follow order: a Move whose message
## names a target reads its destination from the target's position every tick, so the mover
## follows it. The whole actuation of CONTACT mechanics (a capture, a liberation, a crush): the
## point is to arrive on the piece, and a plain move to where it stood arrives on empty
## ground. The engine ends the order itself when the target leaves play (captured and taken
## off the tree: CommandReceiver._target_has_left_play); for a target that DIES the message
## falls back to `world_position`, set here to where the target was at issue, so the mover
## finishes the walk rather than heading for the map origin.
func move_at(a_units: Array, a_target: Entity) -> void:
	if _map == null or a_target == null or not is_instance_valid(a_target):
		return
	for u: Actor in a_units:
		var msg := CommandMessage.new(_map, a_target, null, a_target.global_position)
		if not _admits(MoveCommand, u, msg, "move_at", u.id):
			continue
		var cmd := MoveCommand.new(msg)
		u.update_commands(cmd)
		u.load_destination(cmd)


## Set where `a_structures` send what they produce: a plain move to a world position, which
## is exactly what a player's right-click with a producer selected sets (Actor.set_rally).
## No unit is ordered here — Production hands the rally to each unit as it finishes it.
func rally(a_structures: Array, a_world_pos: Vector3) -> void:
	if _map == null:
		return
	var dest: Vector3 = _map.nearest_navmesh_point(a_world_pos)
	for s: Actor in a_structures:
		usage.record_action("rally", s.id, BotUsageLog.OUTCOME_ISSUED)
		s.set_rally(MoveCommand.new(CommandMessage.new(_map, null, null, dest)))


## Turn every host in `a_hosts` out: the Evacuate order the player gives a garrison. Issued
## to the HOST, so a neutral building the bot's units occupied (and so adopted) takes it like
## one of its own. A host whose occupants may not leave by order is skipped, exactly as the
## command's own precondition would refuse the player.
func evacuate(a_hosts: Array) -> void:
	if _map == null:
		return
	for host: Actor in a_hosts:
		var msg := CommandMessage.new(_map, null, null, host.global_position)
		if _admits(Evacuate, host, msg, "evacuate", host.id):
			host.update_commands(Evacuate.new(msg))


## Order each unit to attack a specific enemy entity directly. persist=false makes
## it a leashed engagement (drop the target if it flees / leaves range), so the unit
## returns to idle — and gets re-tasked — instead of chasing forever.
##
## A UNIT THAT CANNOT TOUCH THE TARGET IS SKIPPED, and this is the guard rather than a
## nicety. `Actor.update_commands` does not consult preconditions — that is the
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
	for u: Actor in a_units:
		var msg := CommandMessage.new(_map, a_target)
		msg.persist = a_persist
		if not _admits(Attack, u, msg, "attack", u.id):
			continue
		var cmd := Attack.new(msg)
		u.update_commands(cmd)
		u.load_destination(cmd)


## Order a builder to place a structure of `type` at a world position. For an Extractor
## (overlay), world_pos must sit on the target ExtractionSite's cell. Tech/resource/
## placement validity are enforced downstream by Build.meets_precondition, so an
## invalid request is a safe no-op (the builder just won't complete it).
func build(
	a_builder: Actor, a_type: StringName, a_world_pos: Vector3, a_quarter_turns: int = 0
) -> bool:
	var tool := Tool.for_type(a_type)
	if tool == null:
		usage.record_action("build", a_type, REFUSED_NO_TOOL)
		return false
	var msg := CommandMessage.new(_map, null, tool, a_world_pos)
	msg.quarter_turns = a_quarter_turns
	# Asked the way the player's click is, so a refusal is counted with its cause rather than
	# left for the builder to discover at the site. The order is still issued either way: Build
	# funds and places lazily, and a cause that clears on the walk (resources) is not a reason
	# to hold the builder — but one that will not (tech, placement) is what the audit wants.
	var cause: MoveCommand.PreconditionFailureCause = Build.meets_precondition(a_builder, msg)
	usage.record_action(
		"build",
		a_type,
		(
			BotUsageLog.OUTCOME_ISSUED
			if cause == MoveCommand.PreconditionFailureCause.NONE
			else BotUsageLog.refused(cause)
		)
	)
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
## available) is Interact.meets_precondition's, asked here so a refusal is counted. Returns
## whether the order was issued.
func interact(a_unit: Actor, a_target: Entity) -> bool:
	if _map == null or a_target == null:
		return false
	var msg := CommandMessage.new(_map, a_target)
	if not _admits(Interact, a_unit, msg, "interact", a_unit.id):
		return false
	var cmd := Interact.new(msg)
	a_unit.update_commands(cmd)
	a_unit.load_destination(cmd)
	return true


## Order [unit] to enter [host]'s garrison. The Occupy precondition — GROUNDED movement, a
## same-team or neutral, built host whose masks admit the unit — is asked here, so a unit
## the host would never take is refused and counted rather than ordered to stand at the
## door. Recorded under the HOST's id: the ledger's question is which hosts the bot uses.
## Returns whether the order was issued.
func garrison_into(a_unit: Actor, a_host: Actor) -> bool:
	if _map == null or a_host == null:
		return false
	var msg := CommandMessage.new(_map, a_host, null, a_host.global_position)
	if not _admits(Occupy, a_unit, msg, "garrison", a_host.id):
		return false
	var cmd := Occupy.new(msg)
	a_unit.update_commands(cmd)
	a_unit.load_destination(cmd)
	return true


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
## sanction with cargo takes its default. `a_target` is the unit a single-unit cast names
## (Sanction.targets_one_unit), null for every other kind.
func use_sanction(
	a_caster: Actor, a_sanction: Sanction, a_world_pos: Vector3, a_target: Entity = null
) -> bool:
	if _map == null or a_caster == null or a_sanction == null:
		return false
	var msg := CommandMessage.new(_map, a_target, null, a_world_pos)
	msg.sanction = a_sanction
	if not _admits(UseSanction, a_caster, msg, "use_sanction", a_sanction.ability_id):
		return false
	if a_sanction.needs_target:
		usage.record_cast_position(a_sanction.ability_id, a_world_pos)
	a_caster.update_commands(UseSanction.new(msg))
	return true


## Order `a_caster` to use its own LOCAL ability `a_ability_id` at `a_world_pos` — the Ability
## command the player's `command_launch` issues, carrying the id on the message. The caster
## walks into the ability's reach and puts the payload down. Recorded under the ability's id,
## like a sanction, so the audit reads abilities by what was cast rather than by who cast it.
## Returns whether the order was issued.
func use_ability(a_caster: Actor, a_ability_id: StringName, a_world_pos: Vector3) -> bool:
	if _map == null or a_caster == null or a_ability_id == &"":
		return false
	var msg := CommandMessage.new(_map, null, null, a_world_pos, a_ability_id)
	if not _admits(Ability, a_caster, msg, "use_ability", a_ability_id):
		return false
	usage.record_cast_position(a_ability_id, a_world_pos)
	var cmd := Ability.new(msg)
	a_caster.update_commands(cmd)
	a_caster.load_destination(cmd)
	return true


## Order `a_spotter` to call in a firing solution on `a_world_pos`: walk into spotting reach,
## channel, and hold the beacon until a Bombard fires on it (Spot). The gun answers on its
## own — automatic fire is the Bombard's default — so this is the bot's whole half of the
## siege loop. Recorded under the Spot ability's id. Returns whether the order was issued.
func spot(a_spotter: Actor, a_world_pos: Vector3) -> bool:
	if _map == null or a_spotter == null:
		return false
	var msg := CommandMessage.new(_map, null, null, a_world_pos)
	if not _admits(Spot, a_spotter, msg, "spot", Spot.ABILITY_ID):
		return false
	usage.record_cast_position(Spot.ABILITY_ID, a_world_pos)
	var cmd := Spot.new(msg)
	a_spotter.update_commands(cmd)
	a_spotter.load_destination(cmd)
	return true


## Queue one unit of `type` at a production structure. Returns false only when no tool
## produces `type`. The purchase goes onto the commander's global production queue,
## which deducts the cost and hands the job to `structure` as soon as it's affordable —
## so a too-expensive request is banked, not dropped. Submitted straight to the queue
## rather than as a Train command so the structure stops reading as idle in the SAME
## tick (see Bot.get_idle_production_structures), which is what stops the bot
## re-ordering the unit it just ordered.
func train(a_structure: Actor, a_type: StringName) -> bool:
	var tool := Tool.for_type(a_type)
	if tool == null or a_structure.commander == null:
		usage.record_action("train", a_type, REFUSED_NO_TOOL)
		return false
	usage.record_action("train", a_type, BotUsageLog.OUTCOME_ISSUED)
	a_structure.commander.production_queue.submit_train(tool, [a_structure])
	return true
