extends GutTest

## THE DECISION SIDE OF A RIDE: BotEscort claims a transport into an escort squad beside the
## squad with the longest way to go, outside the squad cap (an escort is attached to the squad
## it serves, not a second body), and gives it back when there is nothing to carry
## (gdd/systems/ai/squads-and-relations.md §Relations).


## Owns exactly the pieces the test hands it; the squad registry is the real one.
class FakeBot:
	extends Bot
	var own: Array = []

	func get_units() -> Array:
		return own.filter(func(p: Actor) -> bool: return not p.is_in_group("structure"))

	func get_structures() -> Array:
		return own.filter(func(p: Actor) -> bool: return p.is_in_group("structure"))


class RecordingActuator:
	extends BotActuator
	var garrisoned: Array = []  # [{"unit", "host"}]
	var moves: Array = []

	func garrison_into(a_unit: Actor, a_host: Actor) -> bool:
		garrisoned.append({"unit": a_unit, "host": a_host})
		a_unit.update_commands(
			Occupy.new(CommandMessage.new(null, a_host, null, a_host.global_position))
		)
		return true

	func move(a_units: Array, a_world_pos: Vector3) -> void:
		moves.append({"units": a_units.duplicate(), "to": a_world_pos})

	func attack_move(
		_a_units: Array,
		_a_world_pos: Vector3,
		_a_target_priority: Entity.TargetPriority = Entity.TargetPriority.NON_COMBAT_STRUCTURES
	) -> void:
		pass

	func evacuate(_a_hosts: Array) -> void:
		pass


const DESTINATION: Vector3 = Vector3(100.0, 0.0, 0.0)
const CARRIER: Dictionary = {"speed": 8.0, "garrison": {"capacity": 4, "bunker": false}}

var _bot: FakeBot
var _act: RecordingActuator
var _escort: BotEscort
var _main: Squad


func before_each() -> void:
	_bot = FakeBot.new()
	_bot.id = 1
	add_child_autofree(_bot)
	_act = RecordingActuator.new(null)
	_escort = BotEscort.new(_bot, _act)
	_main = _bot.squads.create(&"main")
	_main.policy = HoldPolicy.new(_act, DESTINATION, 1.0)


func _piece(a_options: Dictionary, a_at: Vector3 = Vector3.ZERO) -> Actor:
	var piece: Actor = FakePieces.unit(a_options)
	add_child_autofree(piece)
	piece.ownership.commander = _bot
	piece.global_position = a_at
	_bot.own.append(piece)
	return piece


## A slow soldier in `a_squad` at `a_x`.
func _walker(a_x: float, a_squad: Squad = null) -> Actor:
	var unit: Actor = _piece({"speed": 1.0, "weapon": {"ground": 6.0}}, Vector3(a_x, 0.0, 0.0))
	(a_squad if a_squad != null else _main).add(unit)
	return unit


func test_a_transport_is_claimed_into_an_escort_squad_and_collects_the_slow() -> void:
	var carrier: Actor = _piece(CARRIER)
	_walker(2.0)
	_walker(3.0)
	_escort.tick()
	assert_true(_escort.claims.owns(carrier, BotEscort.CLAIM_OWNER), "held as an errand")
	assert_not_null(_escort.squad(), "an escort squad")
	assert_eq(_escort.squad().name, BotEscort.SQUAD_NAME)
	assert_eq(_escort.squad().policy.kind(), &"escort")
	assert_eq(_bot.squads.count(), 2, "registered beside the main squad")
	assert_eq(_act.garrisoned.size(), 2, "and the policy ran: both called aboard")


func test_the_escort_is_outside_the_squad_cap() -> void:
	# An escort is attached to the squad it serves: the transport carrying the wave is the
	# wave's body, not a second one (Alex, 2026-10-10). BotEscort takes no cap at all, so a
	# bot whose military runs every squad its cap allows still lifts its slow infantry.
	_piece(CARRIER)
	_walker(2.0)
	_bot.squads.create(&"reserve").add(_piece({"speed": 1.0, "weapon": {"ground": 6.0}}))
	_bot.squads.create(&"guard").add(_piece({"speed": 1.0, "weapon": {"ground": 6.0}}))
	_escort.tick()
	assert_not_null(_escort.squad(), "three bodies out, and the lift still runs")
	assert_false("squad_cap" in _escort, "no cap parameter to push")


func test_a_carrier_another_manager_holds_is_not_taken() -> void:
	var carrier: Actor = _piece(CARRIER)
	_walker(2.0)
	_escort.claims.claim(carrier, &"economy", BotClaims.Priority.ERRAND)
	_escort.tick()
	assert_false(_escort.claims.owns(carrier, BotEscort.CLAIM_OWNER))
	assert_null(_escort.squad())
	assert_eq(_act.garrisoned, [])


func test_a_hold_that_admits_none_of_the_squad_is_not_a_carrier() -> void:
	_piece({"speed": 8.0, "garrison": {"capacity": 3, "bunker": false, "ids": [&"fake_builder"]}})
	_walker(2.0)
	_escort.tick()
	assert_null(_escort.squad(), "the truck carries Servants, not soldiers")


func test_the_carrier_is_given_back_when_there_is_nothing_to_carry() -> void:
	var carrier: Actor = _piece(CARRIER)
	var walker: Actor = _walker(2.0)
	_escort.tick()
	assert_true(_escort.claims.owns(carrier, BotEscort.CLAIM_OWNER))
	# The squad arrives on its own; no lift saves anything now.
	walker.clear_command()
	walker.global_position = DESTINATION
	_escort.tick()
	assert_false(_escort.claims.owns(carrier, BotEscort.CLAIM_OWNER), "released")
	assert_null(_escort.squad())
	assert_eq(_bot.squads.count(), 1, "the escort squad left the registry")


func test_a_squad_riding_in_the_hold_is_still_the_one_being_served() -> void:
	var carrier: Actor = _piece(CARRIER)
	var rider: Actor = _walker(2.0)
	_escort.tick()
	# Aboard: off the field, held by the carrier. The garrison's own mechanics are not under
	# test, so the fixture states the result.
	var hold: Garrison = carrier.get_node("Garrison") as Garrison
	hold._garrisoned = [rider]
	rider.garrisoned_in = hold
	rider.get_parent().remove_child(rider)
	_escort.tick()
	assert_true(_escort.claims.owns(carrier, BotEscort.CLAIM_OWNER), "still on the job")
	assert_eq(_act.moves.size(), 1, "carrying: ordered on to the destination")
	assert_eq(_act.moves[0]["to"], DESTINATION)
	add_child(rider)  # back on the field, so autofree finds it where it left it


func test_it_serves_the_squad_with_the_longest_way_to_go() -> void:
	_piece(CARRIER)
	var short := _bot.squads.create(&"short")
	short.policy = HoldPolicy.new(_act, Vector3(12.0, 0.0, 0.0), 1.0)
	_walker(2.0, short)
	_walker(3.0)
	_walker(4.0)
	_escort.tick()
	assert_eq((_escort.squad().policy as EscortPolicy).consumer, _main)


func test_no_squad_going_anywhere_means_no_escort() -> void:
	_piece(CARRIER)
	_walker(2.0)
	_main.policy = null
	_escort.tick()
	assert_null(_escort.squad())


func test_a_lift_is_wanted_while_a_far_squad_walks_and_the_bot_owns_no_transport() -> void:
	_walker(2.0)
	_walker(3.0)
	_escort.tick()
	assert_true(_bot.lift_wanted, "a hundred units at walking pace, no carrier")
	_piece(CARRIER)
	_escort.tick()
	assert_false(_bot.lift_wanted, "owning one is the end of wanting one")


func test_no_lift_is_wanted_for_a_squad_already_there() -> void:
	_walker(98.0)
	_escort.tick()
	assert_false(_bot.lift_wanted)
