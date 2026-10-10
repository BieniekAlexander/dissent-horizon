class_name BotEscort
extends RefCounted

## BotEscort — the decision side of a Relation's Escort: WHICH provider is put beside WHICH
## squad. Each think it looks for a transport worth attaching to the squad with the longest
## way to go, claims it, and keeps it in an escort squad under an EscortPolicy; the policy does
## the carrying (gdd/systems/ai/squads-and-relations.md §Relations). The transport is given
## back the moment there is nothing to carry, so a scout or the preservation path may have it.
##
## One escort at a time. It is NOT counted against the squad cap (Alex, 2026-10-10): an escort
## is attached to the squad it serves — a transport carrying the wave is the wave's body, not a
## second one — and counting both would double-count the squad. TODO: several escorts (one per
## consumer squad) when a bot fields more than one transport.

## The owner name this module claims carriers under (BotClaims). A lift is an ERRAND: the
## army may not sweep the carrier away between loading and unloading.
const CLAIM_OWNER: StringName = &"escort"
## The escort squad's name on the commander's registry.
const SQUAD_NAME: StringName = &"escort"
## Work units per squad and per owned piece looked at (BotScheduler counts work in units of
## roughly a microsecond on the calibration machine).
## Measured 2026-10-10 after the provider-only relation read: 4.4 µs a unit at the old weights.
const SQUAD_WORK_UNITS: int = 35
const PIECE_WORK_UNITS: int = 18

## Which manager owns which unit; the brain replaces this with the bot's shared registry.
var claims: BotClaims = BotClaims.new()

var _bot: Bot
var _act: BotActuator
## The escort squad while one is running, else null. Created on the registry when a carrier
## is claimed and released from it when the carrier is given back, so the cap counts it only
## while it exists.
var _squad: Squad = null


func _init(a_bot: Bot, a_act: BotActuator) -> void:
	_bot = a_bot
	_act = a_act


## Returns the work units spent.
func tick() -> int:
	var work: int = SQUAD_WORK_UNITS * _bot.squads.count()
	var carrier: Actor = _current_carrier()
	var relation: Relation = Relation.transport()
	var consumer: Squad = _consumer_squad()
	# The demand signal production reads (Bot.lift_wanted): a squad is going somewhere far
	# enough that a lift would save it MIN_SAVING_SECONDS at a transport's pace, and the bot owns
	# no transport. Read off the consumer squad's walk rather than off a carrier it has not got.
	_bot.lift_wanted = (
		carrier == null
		and consumer != null
		and _bot.providers_of(relation).is_empty()
		and _lift_would_pay(consumer)
	)
	if carrier == null:
		if consumer == null:
			return work
		var candidates: Array = _bot.providers_of(relation).filter(
			func(piece: Actor) -> bool: return _is_free(piece)
		)
		work += PIECE_WORK_UNITS * candidates.size()
		carrier = _pick_carrier(relation, candidates, consumer)
		if carrier == null:
			return work
		claims.claim(carrier, CLAIM_OWNER, BotClaims.Priority.ERRAND)
		_squad = _bot.squads.create(SQUAD_NAME)
		_squad.add(carrier)
		_squad.eligible = func(unit: Actor) -> bool: return claims.owns(unit, CLAIM_OWNER)
	if consumer != null:
		var policy := EscortPolicy.new(_bot, _act, relation, consumer)
		policy.passenger_eligible = func(unit: Actor) -> bool: return not claims.is_claimed(unit)
		if _squad.policy == null or not _squad.policy.same_as(policy):
			_squad.policy = policy
	# With no squad going anywhere the STANDING policy is still issued: its consumer's
	# destination reads null and the policy lets any passengers out where the carrier stands
	# (EscortPolicy), rather than holding them aboard a transport nobody serves. TODO: a
	# passenger still walking to it keeps its Occupy and boards; nothing turns it round yet.
	_squad.tick()
	_release_if_idle(carrier, true)
	return work


## The escort squad, or null while none runs — for the harness and the debug overlay.
func squad() -> Squad:
	return _squad


## Whether a lift would save `a_consumer`'s mean member at least EscortPolicy.MIN_SAVING_SECONDS
## at a reference carrier pace — a transport the bot might buy, not one it has — judged from the
## squad's centroid to its destination, as the policy judges a real carrier beside the squad.
func _lift_would_pay(a_consumer: Squad) -> bool:
	var where: Variant = a_consumer.policy.destination() if a_consumer.policy != null else null
	var members: Array = a_consumer.fielded()
	if where == null or members.is_empty():
		return false
	var walk: float = VU.in_xz(Bot.centroid_of(members)).distance_to(VU.in_xz(where))
	var slowest: float = INF
	for unit: Actor in members:
		var speed: float = Relation.speed_of(unit)
		if speed > 0.0:
			slowest = minf(slowest, speed)
	if slowest == INF:
		return false
	var saving: float = EscortPolicy.lift_saving_seconds(
		walk, 0.0, walk, slowest, REFERENCE_TRANSPORT_SPEED
	)
	return saving >= EscortPolicy.MIN_SAVING_SECONDS


## The pace a transport the bot does not own yet is assumed to fly at, in world units per
## second, for the demand signal only: the slowest shipped transport (the War Wagon's STEADY)
## rather than the fastest, so the signal does not promise a lift a slower carrier cannot pay
## back. A balance knob, not a derivation — the ladder names its own speeds.
const REFERENCE_TRANSPORT_SPEED: float = 4.0


#region Choosing
## The squad with the longest way to go: a registered squad (not ours) whose policy names a
## destination and whose members' way to it is the longest in total. Null when no squad is
## going anywhere. MEMBERS, not the fielded ones, read where they ARE (`Actor.world_position`:
## a passenger's is its carrier's): a squad riding in our hold is off the field but still on
## its way, and reading only the field made the escort drop a full carrier mid-flight
## (sims/bot/escort/lift_the_slow_squad, 2026-10-10).
func _consumer_squad() -> Squad:
	var best: Squad = null
	var best_walk: float = 0.0
	for squad: Squad in _bot.squads.all():
		if squad == _squad or squad.policy == null:
			continue
		var where: Variant = squad.policy.destination()
		if where == null:
			continue
		var to: Vector2 = VU.in_xz(where)
		var walk: float = 0.0
		for unit: Actor in squad.members():
			walk += VU.in_xz(unit.world_position()).distance_to(to)
		if walk > best_walk:
			best_walk = walk
			best = squad
	return best


## The carrier this module holds, or null — dropping a claim on a carrier that has died.
func _current_carrier() -> Actor:
	for unit: Variant in claims.units_of(CLAIM_OWNER):
		if is_instance_valid(unit) and (unit as Actor).is_inside_tree():
			return unit
	return null


## Among `a_candidates`, the provider nearest the consumers that serves at least one of them;
## null when none does (a truck that admits only builders serves no soldier).
func _pick_carrier(a_relation: Relation, a_candidates: Array, a_consumer: Squad) -> Actor:
	var members: Array = a_consumer.fielded()
	if members.is_empty():
		return null
	var centre: Vector2 = VU.in_xz(Bot.centroid_of(members))
	var best: Actor = null
	var best_distance: float = INF
	for carrier: Actor in a_candidates:
		if not members.any(func(unit: Actor) -> bool: return a_relation.serves(carrier, unit)):
			continue
		var distance: float = carrier.xz_position.distance_to(centre)
		if distance < best_distance:
			best_distance = distance
			best = carrier
	return best


## A provider nobody holds as strongly as an errand, not mid-construction and not on one.
func _is_free(a_piece: Actor) -> bool:
	return (
		a_piece.is_inside_tree()
		and claims.can_claim(a_piece, CLAIM_OWNER, BotClaims.Priority.ERRAND)
		and not BotEconomy._is_constructing(a_piece)
		and not BotOpportunist.is_committed(a_piece)
	)


#endregion


#region Releasing
## Give the carrier back once it is idle, empty and — when the policy was issued this think
## (`a_served`) — its last issue found nothing to do; or when another manager has taken it.
## An issue from an earlier think says nothing about now, which is why it is not read when
## the policy was skipped. The squad goes with the carrier, so the cap frees.
func _release_if_idle(a_carrier: Actor, a_served: bool) -> void:
	if not is_instance_valid(a_carrier):
		_drop_squad()
		return
	if not claims.owns(a_carrier, CLAIM_OWNER):
		_drop_squad()
		return
	var hold: Garrison = a_carrier.get_node_or_null("Garrison") as Garrison
	var carrying: bool = hold != null and hold.occupants().any(hold.can_release_occupant)
	var policy: EscortPolicy = _squad.policy as EscortPolicy if _squad != null else null
	var busy: bool = (
		a_carrier.has_command()
		or carrying
		or (
			a_served
			and policy != null
			and policy.last_action(a_carrier) != EscortPolicy.Action.NONE
		)
	)
	if busy:
		return
	claims.release(a_carrier, CLAIM_OWNER)
	_drop_squad()


func _drop_squad() -> void:
	if _squad == null:
		return
	_bot.squads.release(_squad)
	_squad = null
#endregion
