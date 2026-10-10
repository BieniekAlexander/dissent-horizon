class_name EscortPolicy
extends SquadPolicy

## KEEP A PROVIDER SERVING A CONSUMER SQUAD: the policy of an escort squad, whose members
## PROVIDE a Relation to the members of another squad — a transport carrying the slow half of
## the wave, in time a healer kept beside it. The consumer squad decides where everyone is
## going (its own policy's destination); this policy decides nothing but how its provider
## gets the consumers there. gdd/systems/ai/squads-and-relations.md §Relations.
##
## THE TRANSPORT RUN IS A SEQUENCE WITH NO QUEUE AND NO STATE MACHINE. The bot never queues
## commands (bot-architecture.md §The bot never queues commands), and a plan object held
## across ticks is a second copy of the world that drifts from it. Instead the run is read off
## the world each time the carrier is IDLE — which Squad.tick re-issues every think — and one
## replacement order is given:
##   • carrying releasable passengers, at the destination   → Evacuate;
##   • carrying passengers, nobody else still walking in    → Move to the destination;
##   • carrying passengers, some still walking in           → hold still (no order);
##   • empty, passengers walking in                         → hold still;
##   • empty, a lift worth taking, carrier far from them    → Move to their centroid;
##   • empty, a lift worth taking, carrier beside them      → Occupy each passenger INTO it;
##   • otherwise                                            → nothing (it is free to release).
## A passenger that dies, boards, or is re-tasked simply changes what the next read sees. The
## one piece of state is WHEN loading began, so a passenger that never arrives cannot hold the
## carrier for the match.
##
## Only CONTAINED is built. TODO: RADIUS — a provider kept within reach of the consumers (a
## healer, the Warlord's retinue) — is a follow order re-issued on idle, once a RADIUS relation
## the bot can actuate exists (no Repair verb in BotActuator yet). POINT is BotAbilities'
## siege loop and stays there.

## A lift is taken only when it saves each passenger at least this many SECONDS over walking.
## A balance knob: the time a player would reckon worth the loading fuss.
const MIN_SAVING_SECONDS: float = 8.0
## Seconds charged to every lift for boarding and unloading, on top of the flight.
const BOARDING_OVERHEAD_SECONDS: float = 4.0
## A carrier this close to its passengers (world units) holds still and calls them aboard;
## farther, it goes to them first.
const PICKUP_RADIUS: float = 8.0
## A carrier this close to the destination (world units) unloads.
const UNLOAD_RADIUS: float = PostPolicy.HOLD_RADIUS * 2.0
## Seconds after the first Occupy was issued before the carrier stops waiting for stragglers:
## it departs with whoever is aboard, and the rest walk.
const LOAD_TIMEOUT_SECONDS: float = 15.0

## What the last issue did for a carrier, for the decision side and the harness.
enum Action { NONE, APPROACH, COLLECT, WAIT, CARRY, UNLOAD }

var relation: Relation
## The squad being served. Its policy's destination is where the passengers go.
var consumer: Squad
## Which consumer members may be carried right now; the decision side excludes a unit another
## manager holds (mid-fight, on an errand). Admits everyone by default.
var passenger_eligible: Callable = func(_a_unit: Actor) -> bool: return true

var _bot: Bot
var _act: BotActuator
## Carrier instance id → seconds_elapsed when its current loading began.
var _loading_since: Dictionary = {}
## Carrier instance id → the Action the last issue took for it.
var _last_action: Dictionary = {}


func _init(a_bot: Bot, a_act: BotActuator, a_relation: Relation, a_consumer: Squad) -> void:
	_bot = a_bot
	_act = a_act
	relation = a_relation
	consumer = a_consumer


func kind() -> StringName:
	return &"escort"


## The same service: the same relation to the same squad. Where the consumers are going may
## change every think; that is read at issue, not compared here.
func same_as(a_other: SquadPolicy) -> bool:
	return (
		a_other is EscortPolicy
		and (a_other as EscortPolicy).relation.name == relation.name
		and (a_other as EscortPolicy).consumer == consumer
	)


## Where the consumers are going, or null while their policy has no destination.
func destination() -> Variant:
	return consumer.policy.destination() if consumer != null and consumer.policy != null else null


## What the last issue did for `a_carrier`; NONE for a carrier it has not served.
func last_action(a_carrier: Actor) -> Action:
	return _last_action.get(a_carrier.get_instance_id(), Action.NONE)


func issue(a_members: Array) -> void:
	if relation.reach != Relation.Reach.CONTAINED:
		return  # TODO: RADIUS and POINT — see the class note.
	var where: Variant = destination()
	for carrier: Actor in a_members:
		_last_action[carrier.get_instance_id()] = _serve(carrier, where)


#region The run
## One read of the world and one order for an idle carrier — the table in the class note.
func _serve(a_carrier: Actor, a_destination: Variant) -> Action:
	var hold: Garrison = a_carrier.get_node_or_null("Garrison") as Garrison
	if hold == null:
		return Action.NONE
	var aboard: Array = hold.occupants().filter(hold.can_release_occupant)
	var boarding: Array = _boarding(a_carrier)
	if not aboard.is_empty():
		if a_destination == null:
			_act.evacuate([a_carrier])  # the squad has nowhere to go: let them out here
			return Action.UNLOAD
		var to: Vector3 = a_destination
		if a_carrier.xz_position.distance_to(VU.in_xz(to)) <= UNLOAD_RADIUS:
			_loading_since.erase(a_carrier.get_instance_id())
			_act.evacuate([a_carrier])
			return Action.UNLOAD
		if boarding.is_empty() or _waited_too_long(a_carrier):
			_loading_since.erase(a_carrier.get_instance_id())
			_walk_on(boarding, to)
			_act.move([a_carrier], to)
			return Action.CARRY
		return Action.WAIT
	# Empty.
	if a_destination == null:
		return Action.NONE
	var to: Vector3 = a_destination
	if not boarding.is_empty():
		if _waited_too_long(a_carrier):
			_loading_since.erase(a_carrier.get_instance_id())
			_walk_on(boarding, to)
			return Action.NONE
		return Action.WAIT
	var passengers: Array = _pick_passengers(a_carrier, hold, to)
	if passengers.is_empty():
		return Action.NONE
	var centroid: Vector3 = Bot.centroid_of(passengers)
	if a_carrier.xz_position.distance_to(VU.in_xz(centroid)) > PICKUP_RADIUS:
		_act.move([a_carrier], centroid)
		return Action.APPROACH
	for passenger: Actor in passengers:
		_act.garrison_into(passenger, a_carrier)
	_loading_since[a_carrier.get_instance_id()] = _bot.seconds_elapsed()
	return Action.COLLECT


## The consumer's fielded members ordered INTO `a_carrier` and still walking to it.
func _boarding(a_carrier: Actor) -> Array:
	return consumer.fielded().filter(
		func(unit: Actor) -> bool:
			var order: MoveCommand = unit.current_command()
			return (
				order is Occupy
				and order.message != null
				and is_instance_valid(order.message.target)
				and order.message.target == a_carrier
			)
	)


func _waited_too_long(a_carrier: Actor) -> bool:
	var since: Variant = _loading_since.get(a_carrier.get_instance_id(), null)
	return since != null and _bot.seconds_elapsed() - float(since) > LOAD_TIMEOUT_SECONDS


## Stragglers the carrier is not waiting for any longer walk to the destination themselves —
## the order their own squad's policy would give them, so nothing is left holding an Occupy
## at a carrier that has gone.
func _walk_on(a_stragglers: Array, a_destination: Vector3) -> void:
	if not a_stragglers.is_empty():
		_act.attack_move(a_stragglers, a_destination)


## The consumer members worth lifting to `a_destination`, most time saved first, as many as
## fit `a_hold`. A member the relation does not serve (the masks refuse it, it cannot move),
## one another manager holds, or one the lift would not save MIN_SAVING_SECONDS is left to walk.
func _pick_passengers(a_carrier: Actor, a_hold: Garrison, a_destination: Vector3) -> Array:
	var carrier_speed: float = _speed_of(a_carrier)
	if carrier_speed <= 0.0:
		return []
	var to: Vector2 = VU.in_xz(a_destination)
	var from: Vector2 = a_carrier.xz_position
	var scored: Array = []  # [saving, unit]
	for unit: Actor in consumer.fielded():
		if not passenger_eligible.call(unit) or not relation.serves(a_carrier, unit):
			continue
		var walker_speed: float = _speed_of(unit)
		if walker_speed <= 0.0:
			continue
		var at: Vector2 = unit.xz_position
		var saving: float = lift_saving_seconds(
			at.distance_to(to),
			from.distance_to(at),
			at.distance_to(to),
			walker_speed,
			carrier_speed
		)
		if saving >= MIN_SAVING_SECONDS:
			scored.append([saving, unit])
	scored.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var room: int = a_hold.remaining_capacity()
	var picked: Array = []
	for entry: Array in scored:
		var unit: Actor = entry[1]
		var size: int = Garrison.size_of(unit)
		if size <= room:
			picked.append(unit)
			room -= size
	return picked


## SECONDS A LIFT SAVES ONE PASSENGER: the walk it would make, less the carrier's flight to
## it, the boarding and unloading, and the flight on. Straight-line distances throughout — an
## underestimate of a walker's path and an exact one of a flyer's, so the saving is
## conservative where the ground winds. Pure, so the curve is testable without a carrier.
static func lift_saving_seconds(
	walk_distance: float,
	pickup_distance: float,
	carry_distance: float,
	walker_speed: float,
	carrier_speed: float
) -> float:
	var walk: float = walk_distance / walker_speed
	var ride: float = (pickup_distance + carry_distance) / carrier_speed + BOARDING_OVERHEAD_SECONDS
	return walk - ride


## A piece's speed in world units per second, or 0 when it cannot move. Off its Movement rather
## than Bot.mobility_of, which reads the LIVE movement and answers nothing for a carrier on the
## ground taking passengers aboard.
func _speed_of(a_piece: Actor) -> float:
	return Relation.speed_of(a_piece)
#endregion
