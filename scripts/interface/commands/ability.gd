class_name Ability
extends MoveCommand

## Generic position-targeted ability command: the actor closes on the point and puts its
## payload down there.
##
## WHICH ability is carried on `message.ability_type`, a `kind: AbilityDefinition` doc id. It used to
## be a member of an enum declared right here — a second, parallel ability system that ended
## its life holding one member (RADIATION) while `Abilities`/`AbilityCatalog` held everything
## else. Folding it out is what makes "every ability is charge-based, and a charge is the
## universal unit" true without an exception.
##
## Three things moved with it, and each replaced a bespoke copy:
##   * CHARGES — the actor's `Abilities` pool, not an `Inventory` of `ToolSpec`s.
##   * THE PAYLOAD — `AbilityCatalog.emission_of`, not a per-commander payload registry.
##   * AVAILABILITY — the pool grants it or it does not, so the commander's technology map no
##     longer carries int ability keys beside its piece ids.
##
## REACH IS OVERRIDABLE, and that is the fourth. This class used to carry
## `const RANGE: float = 5.0` — one reach for every ability that would ever exist — so an
## ability limited by something other than distance could not be expressed at all, and
## [Bombard] was written as a SIBLING command class duplicating this one's shape. It is now
## a subclass: an ability with an ordinary reach authors `range:` on its doc, and one whose
## reach is not a distance overrides `is_in_range`. See
## gdd/systems/commands/the-click-ladder.md and ~/.claude/CLAUDE.md §1.3.

#region Reach
## Whether [a_actor] may use the ability from where it stands.
##
## THE ONE METHOD A SUBCLASS REPLACES to change what "in range" means. The default is an XZ
## distance test against the ability's own authored reach.
static func is_in_range(actor: Commandable, message: CommandMessage) -> bool:
	if actor == null or message == null:
		return false
	var reach: float = AbilityCatalog.range_of(_ability_of(message))
	return (actor.xz_position - message.xz_position).length_squared() < reach * reach


## Whether walking closer can turn a failing `is_in_range` into a passing one.
##
## True for a distance, so an ordinary ability is offered to a mobile actor wherever it
## stands and refused only to one that could never close the gap. False for a reach that
## is not a distance — no amount of driving makes an unspotted point spotted — and a
## subclass saying so gets the refusal and the no-move behaviour together.
static func range_closes_by_moving() -> bool:
	return true


## How a failing `is_in_range` is reported. Subclasses whose reach means something else
## report it as something else — the Bombard's unspotted point is not bad PLACEMENT.
static func out_of_range_cause() -> PreconditionFailureCause:
	return PreconditionFailureCause.INVALID_PLACEMENT
#endregion

#region Preconditions
static func meets_precondition(
	actor: Commandable,
	message: CommandMessage
) -> PreconditionFailureCause:
	return precondition_for(Ability, actor, message)


## The shared precondition, spelled once and told WHICH class it is speaking for.
##
## The class is a parameter because GDScript resolves an unqualified static call inside
## another STATIC function against the declaring class, not the one it was invoked on — so
## a plain `is_in_range(...)` here would always run Ability's, whatever the subclass. (From
## an INSTANCE method it does dispatch, which is why can_act below needs no such help.)
## Each subclass overriding `meets_precondition` passes itself.
static func precondition_for(
	command_class: Script,
	actor: Commandable,
	message: CommandMessage
) -> PreconditionFailureCause:
	var ability_id: StringName = command_class._ability_of(message)
	if actor == null or ability_id == &"":
		return PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
	var pool: Abilities = _pool_of(actor)
	# Not granted → the unit simply does not have it.
	if pool == null or not pool.grants(ability_id):
		return PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
	# A DARK BUILDING CASTS NOTHING, and unlike a spent charge this is never deferred: the
	# additive modifier queues an order that waiting will fulfil, and waiting does not close
	# an infrastructure shortfall. See Abilities.is_operational.
	if not pool.is_operational():
		return PreconditionFailureCause.UNPOWERED
	# A SPENT CHARGE IS REFUSED, exactly as an unaffordable purchase is — unless the additive
	# modifier is held, which is what asks for the order to be QUEUED and acted on when the
	# charge comes up. Why: gdd/systems/commands/cooldowns-and-preconditions.md.
	if not message.defer_if_unaffordable and not pool.is_ready(ability_id):
		return PreconditionFailureCause.ABILITY_NO_CHARGES
	# Out of reach, and nothing the actor can do about it: either the reach is not a distance
	# at all, or it is and this actor cannot move. Refuse outright rather than leave it
	# holding an order it can never fulfil.
	if not command_class.is_in_range(actor, message) \
			and not (command_class.range_closes_by_moving() and actor.can_move()):
		return command_class.out_of_range_cause()
	return PreconditionFailureCause.NONE
#endregion

## AUTHORED PER ABILITY (`cast_by:`), not per command class: every ability is this same
## command, so the class cannot answer without being told which one. Defaults to SINGLE — see
## AbilityCatalog.cast_arity_of for why that is the right default for an ability.
static func default_cast_arity(message: CommandMessage) -> CastArity:
	return AbilityCatalog.cast_arity_of(_ability_of(message))


## Still reloading. Asked of the ACTOR alone, with no message, so it reads every pool the
## actor has — right for a unit with one ability, which is every case today.
static func actor_is_recharging(actor: Commandable) -> bool:
	var pool: Abilities = _pool_of(actor)
	if pool == null:
		return false
	for id: StringName in pool.granted_abilities():
		if not pool.is_ready(id):
			return true
	return false


#region Private helpers
static func _pool_of(actor: Commandable) -> Abilities:
	return actor.get_node_or_null("Abilities") as Abilities if actor != null else null

## The ability id on the message, or &"" when it carries none. Accepts a StringName written
## straight onto the message; anything else is a caller that has not been moved off the old
## enum, and is refused rather than guessed at.
##
## Overridable: a subclass that IS one particular ability (Bombard) names it outright rather
## than waiting for a caller to write it onto every message.
static func _ability_of(message: CommandMessage) -> StringName:
	if message == null or not (message.ability_type is StringName):
		return &""
	return message.ability_type as StringName
#endregion

#region State updates
## Walk toward the point, unless walking cannot help — a reach that is not a distance is not
## closed by moving, and a gun that stayed put is better than one that wanders.
func should_move(a_actor: Commandable) -> bool:
	return range_closes_by_moving() and not can_act(a_actor)

## In range AND holding a charge. The charge half is load-bearing: `fulfill_action` returns
## null when the spend fails, and a null return DROPS the command (CommandReceiver sets
## `_command = null`) — so without this a queued ability whose charge was spent was silently
## thrown away the moment the actor arrived, instead of waiting out the reload.
func can_act(a_actor: Commandable) -> bool:
	var pool: Abilities = _pool_of(a_actor)
	var ability_id: StringName = _ability_of(message)
	if pool == null or ability_id == &"" or not pool.is_ready(ability_id):
		return false
	return is_in_range(a_actor, message)

## Spend a charge and throw the payload. Null ends the command: one order, one use.
func fulfill_action(a_actor: Commandable) -> Variant:
	var ability_id: StringName = _ability_of(message)
	if not consume(a_actor, ability_id):
		return null
	emit(a_actor, ability_id, message.position)
	return null

## Take the charge this use costs, and anything else the ability spends. False aborts the
## use without emitting. Subclasses extend it — the Bombard also burns the beacon that gave
## it its firing solution.
func consume(a_actor: Commandable, a_ability_id: StringName) -> bool:
	var pool: Abilities = _pool_of(a_actor)
	return pool != null and a_ability_id != &"" and pool.spend(a_ability_id)

## Throw the ability's payload at [a_target_position]. Ability payloads are emissions,
## added directly via initialize() rather than map.add_entity — that path runs
## unit-placement spreading and expects a MOVEMENT_OBSTRUCTION shape projectiles do not
## have. Returns false when the ability emits nothing.
func emit(a_actor: Commandable, a_ability_id: StringName, a_target_position: Vector3) -> bool:
	return launch_emission(a_actor, a_ability_id, a_target_position) != null

## Throw the ability's payload at `a_target` — a point, or an Entity to pursue (see
## Emitter.launch) — and return the emission, or null when the ability emits nothing.
func launch_emission(a_actor: Commandable, a_ability_id: StringName, a_target: Variant) -> Entity:
	var scene: PackedScene = AbilityCatalog.emission_of(a_ability_id)
	if scene == null:
		push_error("ability '%s' emits nothing to lay down" % a_ability_id)
		return null
	var projectile: Entity = scene.instantiate() as Entity
	if projectile == null:
		return null
	# message.map when the order carries one, the actor's otherwise — the idiom every other
	# command that spawns something uses (see Interact, Spot, Wander).
	projectile.initialize(message.map if message != null and message.map != null else a_actor.map,
		a_actor.commander)
	projectile.global_position = a_actor.global_position
	Emitter.launch(projectile, a_actor, a_target)
	return projectile
#endregion
