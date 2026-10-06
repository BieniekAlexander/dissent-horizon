class_name UseSanction
extends MoveCommand

## Cast one of the commander's unlocked sanctions FROM a building that is allowed to.
##
## One command class for every sanction, with the sanction itself on the message
## (`CommandMessage.sanction`), because sanctions are authored data: a faction adds one by
## writing a markdown doc, and a class-per-sanction would put code in the way of that.
##
## THREE SEPARATE GATES, and keeping them apart is the design:
##   • the SANCTION GRID says whether this side has the ability at all (dominion, tiers, the
##     parent chain) — `SanctionGrid.is_unlocked`;
##   • the CASTER says who may use it — the sanction names a piece id, and only a finished
##     building of that id qualifies;
##   • the CHARGE says how often — a pool on the building, SHARED by every ability in the
##     same group (see Abilities).
##
## So unlocking Scan does not let the commander scan; it lets every Operations Center they
## own scan, once each, on independent timers. Losing the building loses the ability.


#region Preconditions
static func meets_precondition(
	actor: Commandable, message: CommandMessage
) -> MoveCommand.PreconditionFailureCause:
	var sanction: Sanction = message.sanction if message != null else null
	if actor == null or sanction == null or actor.commander == null:
		return PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
	# Not a caster for this sanction, or not finished being built.
	var abilities: Abilities = _abilities_of(actor)
	if abilities == null or not abilities.grants(sanction.ability_id) or not actor.is_built:
		return PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
	# Not unlocked (or superseded by an upgrade).
	if (
		actor.commander.sanction_grid == null
		or not actor.commander.sanction_grid.is_unlocked(sanction)
	):
		return PreconditionFailureCause.MISSING_STRUCTURE
	# A DARK BUILDING CASTS NOTHING. Never deferred, unlike a spent charge: waiting closes a
	# cooldown, not an infrastructure shortfall. See Abilities.is_operational.
	if not abilities.is_operational():
		return PreconditionFailureCause.UNPOWERED
	# A SPENT POOL IS REFUSED unless the additive modifier is held, which is what asks for the
	# cast to be queued and fired when the charge comes up. The button greys either way (see
	# actor_is_recharging). Why: gdd/systems/commands/cooldowns-and-preconditions.md.
	if not message.defer_if_unaffordable and not abilities.is_ready(sanction.ability_id):
		return PreconditionFailureCause.ABILITY_NO_CHARGES
	# A single-unit cast names its unit, and without one there is nothing to cast on — so the
	# order is not given at all, and no charge is spent. See EventTargetUnit.
	if sanction.targets_one_unit() and not sanction.accepts_target(message.target, actor.commander):
		return PreconditionFailureCause.NO_VALID_TARGET
	if sanction.needs_target and not sanction.can_target(message.position, actor.commander):
		return PreconditionFailureCause.TARGET_NOT_SPOTTED
	return PreconditionFailureCause.NONE


static func requires_position() -> bool:
	return true


## The same authored `cast_by:` an ordinary ability reads, reached through the sanction's own
## ability id — a sanction is one UNLOCK ROUTE to an ability, not a different kind of thing,
## so it must not answer this differently.
static func default_cast_arity(message: CommandMessage) -> CastArity:
	var sanction: Sanction = message.sanction if message != null else null
	return (
		AbilityCatalog.cast_arity_of(sanction.ability_id) if sanction != null else CastArity.SINGLE
	)


## Free unless already casting one — the job rule (MoveCommand.is_free_to_take).
static func is_free_to_take(actor: Commandable) -> bool:
	return holds_none_of(actor, [UseSanction])


## The charge is spent, so the button greys; the order is still accepted and waits.
static func actor_is_recharging(actor: Commandable) -> bool:
	var abilities: Abilities = _abilities_of(actor)
	if abilities == null or actor.commander == null:
		return false
	var castable: Array[Sanction] = actor.commander.sanctions_castable_by(actor)
	if castable.is_empty():
		return false
	# Every ability this building offers is down. Matching MoveCommand.actor_is_recharging's
	# contract, which is asked of the ACTOR with no message and so cannot name one ability.
	for sanction: Sanction in castable:
		if abilities.is_ready(sanction.ability_id):
			return false
	return true


static func _abilities_of(actor: Commandable) -> Abilities:
	return actor.get_node_or_null("Abilities") as Abilities if actor != null else null


#endregion


#region State updates
## A building does not travel to its target — its reach is the sanction's own.
func should_move(_a_actor: Commandable) -> bool:
	return false


func can_act(a_actor: Commandable) -> bool:
	var abilities: Abilities = _abilities_of(a_actor)
	return (
		abilities != null
		and message.sanction != null
		and abilities.is_ready(message.sanction.ability_id)
	)


## One order, one casting. Returning null ends the command rather than leaving the building
## re-firing at a point the player asked about once.
func fulfill_action(a_actor: Commandable) -> Variant:
	var sanction: Sanction = message.sanction
	var abilities: Abilities = _abilities_of(a_actor)
	if sanction == null or abilities == null or a_actor.commander == null:
		return null
	var manager: ScenarioTriggerManager = a_actor.commander.scenario_event_manager()
	if manager == null:
		return null
	# The chosen cargo, for a sanction that takes one. `message.tool` is set by the payload
	# menu exactly as it is by the build list — one field, one meaning: "the thing this order
	# is about". A sanction with no payloads ignores it.
	var payload: StringName = message.tool.type if message.tool != null else &""
	if not sanction.activate(
		message.position, manager, a_actor.commander, a_actor, payload, message.target
	):
		return null
	abilities.spend(sanction.ability_id)
	return null
#endregion
