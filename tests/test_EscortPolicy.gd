extends GutTest

## THE TRANSPORT RUN, read off the world on every idle issue rather than queued or planned:
## collect the passengers a lift saves time for, wait for them, carry, unload — and a
## straggler cannot hold the carrier past the loading window
## (gdd/systems/ai/squads-and-relations.md §Relations, EscortPolicy's class note).


## The clock is the test's.
class FakeBot:
	extends Bot
	var now: float = 0.0

	func seconds_elapsed() -> float:
		return now


## Records orders instead of issuing them. A garrison order leaves the passenger holding an
## Occupy at the host, as the real one would, so the next issue sees it boarding.
class RecordingActuator:
	extends BotActuator
	var garrisoned: Array = []  # [{"unit", "host"}]
	var moves: Array = []  # [{"units", "to"}]
	var evacuated: Array = []
	var attack_moves: Array = []  # [{"units", "to"}]

	func garrison_into(a_unit: Actor, a_host: Actor) -> bool:
		garrisoned.append({"unit": a_unit, "host": a_host})
		a_unit.update_commands(
			Occupy.new(CommandMessage.new(null, a_host, null, a_host.global_position))
		)
		return true

	func move(a_units: Array, a_world_pos: Vector3) -> void:
		moves.append({"units": a_units.duplicate(), "to": a_world_pos})

	func evacuate(a_hosts: Array) -> void:
		evacuated.append_array(a_hosts)

	func attack_move(
		a_units: Array,
		a_world_pos: Vector3,
		_a_target_priority: Entity.TargetPriority = Entity.TargetPriority.NON_COMBAT_STRUCTURES
	) -> void:
		attack_moves.append({"units": a_units.duplicate(), "to": a_world_pos})


const DESTINATION: Vector3 = Vector3(100.0, 0.0, 0.0)
const CARRIER_SPEED: float = 8.0
const WALKER_SPEED: float = 1.0

var _bot: FakeBot
var _act: RecordingActuator
var _carrier: Actor
var _hold: Garrison
var _consumer: Squad
var _policy: EscortPolicy


func before_each() -> void:
	_bot = FakeBot.new()
	_bot.id = 1
	add_child_autofree(_bot)
	_act = RecordingActuator.new(null)
	_carrier = _piece({"speed": CARRIER_SPEED, "garrison": {"capacity": 2, "bunker": false}})
	_hold = _carrier.get_node("Garrison") as Garrison
	_consumer = Squad.new(&"main")
	_consumer.policy = HoldPolicy.new(_act, DESTINATION, 1.0)
	_policy = EscortPolicy.new(_bot, _act, Relation.transport(), _consumer)


func _piece(a_options: Dictionary, a_at: Vector3 = Vector3.ZERO) -> Actor:
	var piece: Actor = FakePieces.unit(a_options)
	add_child_autofree(piece)
	piece.ownership.commander = _bot
	piece.global_position = a_at
	return piece


## A slow soldier in the consumer squad, standing at `a_x` on the carrier's axis.
func _walker(a_x: float, a_speed: float = WALKER_SPEED) -> Actor:
	var unit: Actor = _piece({"speed": a_speed, "weapon": {"ground": 6.0}}, Vector3(a_x, 0.0, 0.0))
	_consumer.add(unit)
	return unit


func _issue() -> void:
	_policy.issue([_carrier])


# ─── THE SAVING ──────────────────────────────────────────────────────────────


func test_a_lift_saves_the_walk_less_the_flight_and_the_boarding() -> void:
	# 100 units at 1/s is 100 s on foot; 100 units at 8/s plus the boarding is 16.5 s.
	var saving: float = EscortPolicy.lift_saving_seconds(100.0, 0.0, 100.0, 1.0, 8.0)
	assert_almost_eq(saving, 100.0 - (12.5 + EscortPolicy.BOARDING_OVERHEAD_SECONDS), 0.001)


func test_a_fast_walker_near_its_destination_gains_nothing() -> void:
	assert_true(EscortPolicy.lift_saving_seconds(10.0, 0.0, 10.0, 4.0, 8.0) < 0.0)


# ─── COLLECTING ──────────────────────────────────────────────────────────────


func test_an_empty_carrier_beside_slow_walkers_calls_them_aboard_farthest_first() -> void:
	var near: Actor = _walker(2.0)
	var middle: Actor = _walker(3.0)
	_walker(4.0)  # the third does not fit a hold of two
	_issue()
	assert_eq(_act.garrisoned.size(), 2, "as many as fit")
	var picked: Array = _act.garrisoned.map(func(o: Dictionary) -> Actor: return o["unit"])
	assert_eq(picked, [near, middle], "the longest walk saved first")
	assert_eq(_act.garrisoned[0]["host"], _carrier)
	assert_eq(_act.moves, [], "the carrier holds still for them")
	assert_eq(_policy.last_action(_carrier), EscortPolicy.Action.COLLECT)


func test_a_second_issue_while_they_walk_in_orders_nobody_again() -> void:
	_walker(2.0)
	_issue()
	_issue()
	assert_eq(_act.garrisoned.size(), 1, "idempotent: they are already coming")
	assert_eq(_policy.last_action(_carrier), EscortPolicy.Action.WAIT)


func test_a_walker_the_lift_would_not_save_is_left_to_walk() -> void:
	_walker(2.0, 10.0)  # 10 s on foot against a 16.5 s ride
	_issue()
	assert_eq(_act.garrisoned, [])
	assert_eq(_policy.last_action(_carrier), EscortPolicy.Action.NONE)


func test_a_carrier_far_from_its_passengers_goes_to_them_first() -> void:
	_carrier.global_position = Vector3(-50.0, 0.0, 0.0)
	_walker(2.0)
	_walker(4.0)
	_issue()
	assert_eq(_act.garrisoned, [], "nobody is called across the map on foot")
	assert_eq(_act.moves.size(), 1)
	assert_eq(_act.moves[0]["units"], [_carrier])
	assert_almost_eq((_act.moves[0]["to"] as Vector3).x, 3.0, 0.001, "to their centroid")
	assert_eq(_policy.last_action(_carrier), EscortPolicy.Action.APPROACH)


func test_a_walker_another_manager_holds_is_not_taken() -> void:
	var held: Actor = _walker(2.0)
	_policy.passenger_eligible = func(unit: Actor) -> bool: return unit != held
	_issue()
	assert_eq(_act.garrisoned, [])


# ─── CARRYING AND UNLOADING ──────────────────────────────────────────────────


func test_a_loaded_carrier_with_nobody_else_coming_departs() -> void:
	var rider: Actor = _walker(2.0)
	_hold._garrisoned = [rider]  # aboard; the garrison's own mechanics are not under test
	_issue()
	assert_eq(_act.moves.size(), 1)
	assert_eq(_act.moves[0]["to"], DESTINATION)
	assert_eq(_act.garrisoned, [], "no second load is called while carrying")
	assert_eq(_policy.last_action(_carrier), EscortPolicy.Action.CARRY)


func test_a_loaded_carrier_at_the_destination_unloads() -> void:
	var rider: Actor = _walker(2.0)
	_hold._garrisoned = [rider]
	_carrier.global_position = DESTINATION + Vector3(1.0, 0.0, 0.0)
	_issue()
	assert_eq(_act.evacuated, [_carrier])
	assert_eq(_act.moves, [])
	assert_eq(_policy.last_action(_carrier), EscortPolicy.Action.UNLOAD)


func test_a_loaded_carrier_waits_for_a_passenger_still_walking_in() -> void:
	var rider: Actor = _walker(2.0)
	var straggler: Actor = _walker(3.0)
	_issue()  # both called aboard
	assert_eq(_act.garrisoned.size(), 2)
	_hold._garrisoned = [rider]
	rider.clear_command()
	_issue()
	assert_eq(_act.moves, [], "the straggler is still coming")
	assert_eq(_policy.last_action(_carrier), EscortPolicy.Action.WAIT)
	# …but not for ever: past the loading window the carrier goes with whoever is aboard, and
	# the straggler walks.
	_bot.now = EscortPolicy.LOAD_TIMEOUT_SECONDS + 1.0
	_issue()
	assert_eq(_act.moves.size(), 1, "departed")
	assert_eq(_act.moves[0]["to"], DESTINATION)
	assert_eq(_act.attack_moves.size(), 1)
	assert_eq(_act.attack_moves[0]["units"], [straggler])
	assert_eq(_act.attack_moves[0]["to"], DESTINATION)
	assert_eq(_policy.last_action(_carrier), EscortPolicy.Action.CARRY)


func test_an_empty_carrier_stops_waiting_for_stragglers_too() -> void:
	var straggler: Actor = _walker(2.0)
	_issue()
	_bot.now = EscortPolicy.LOAD_TIMEOUT_SECONDS + 1.0
	_issue()
	assert_eq(_act.attack_moves.size(), 1)
	assert_eq(_act.attack_moves[0]["units"], [straggler])
	assert_eq(_policy.last_action(_carrier), EscortPolicy.Action.NONE, "free to be given back")


func test_a_squad_going_nowhere_is_let_out_where_the_carrier_stands() -> void:
	var rider: Actor = _walker(2.0)
	_hold._garrisoned = [rider]
	_consumer.policy = null
	_issue()
	assert_eq(_act.evacuated, [_carrier])
	assert_eq(_policy.last_action(_carrier), EscortPolicy.Action.UNLOAD)


func test_an_empty_carrier_with_nowhere_to_go_does_nothing() -> void:
	_walker(2.0)
	_consumer.policy = null
	_issue()
	assert_eq(_act.garrisoned, [])
	assert_eq(_act.moves, [])
	assert_eq(_policy.last_action(_carrier), EscortPolicy.Action.NONE)


# ─── IDENTITY ────────────────────────────────────────────────────────────────


func test_the_same_relation_to_the_same_squad_is_the_same_policy() -> void:
	var again := EscortPolicy.new(_bot, _act, Relation.transport(), _consumer)
	assert_true(_policy.same_as(again))
	var other := EscortPolicy.new(_bot, _act, Relation.transport(), Squad.new(&"other"))
	assert_false(_policy.same_as(other), "a different squad is a different service")
	assert_false(_policy.same_as(HoldPolicy.new(_act, DESTINATION, 1.0)))
	assert_eq(_policy.kind(), &"escort")
	assert_eq(_policy.destination(), DESTINATION, "where the consumers are going")
