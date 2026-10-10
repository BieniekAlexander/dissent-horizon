extends GutTest

## Flushing a garrison: a flushable host's occupants are all killed, by a flushing emission that
## STRIKES the host (never one whose blast merely covers it), or by a Flusher storming a host its
## enemy holds and entering in the same tick.
## Rules: gdd/systems/combat/garrison-and-transport.md §Flushing a garrison.
##
## Run with:
##   python3 tools/gut_shards/gut_shards.py GarrisonFlush

const NEUTRAL_ID: int = 0
const HOLDER_ID: int = 1
const STORMER_ID: int = 2
const SOLDIER: Dictionary = {"speed": 2.0, "weapon": {"ground": 6.0}}
const STORMER: Dictionary = {"speed": 2.0, "flushes": true}

var _commanders: Dictionary = {}


func before_each() -> void:
	_commanders = {}


func _commander(a_id: int) -> Commander:
	if not _commanders.has(a_id):
		var commander := Commander.new()
		commander.id = a_id
		add_child_autofree(commander)
		_commanders[a_id] = commander
	return _commanders[a_id]


func _piece(a_options: Dictionary, a_commander_id: int) -> Actor:
	var piece := FakePieces.make(a_options) as Actor
	add_child_autofree(piece)
	piece.ownership.commander = _commander(a_commander_id)
	return piece


## A neutral building holding `a_count` of HOLDER's soldiers, flushable or not.
func _held_building(a_count: int, a_flushable: bool = true) -> Actor:
	var host: Actor = _piece(
		{"structure": true, "garrison": {"capacity": 4, "flushable": a_flushable}}, NEUTRAL_ID
	)
	for _i: int in a_count:
		host.garrison.garrison(_piece(SOLDIER, HOLDER_ID))
	return host


#region The garrison
func test_a_flush_kills_everyone_inside() -> void:
	var host: Actor = _held_building(3)
	var occupants: Array[Actor] = host.garrison.occupants().duplicate()
	assert_eq(host.garrison.flush(), 3)
	assert_eq(host.garrison.garrisoned_count(), 0)
	for unit: Actor in occupants:
		assert_true(unit.defense.hp <= 0.0, "dead")
	await get_tree().process_frame
	for unit: Actor in occupants:
		assert_false(is_instance_valid(unit), "and gone")


func test_a_flush_is_a_kill_credited_to_whoever_flushed() -> void:
	var host: Actor = _held_building(2)
	var killer: Actor = _piece(STORMER, STORMER_ID)
	var kills: Array = []
	killer.entity_occurrence.connect(
		func(a_occurrence: Entity.EntityOccurrence, _a_entity: Entity) -> void:
			if a_occurrence == Entity.EntityOccurrence.ON_KILL:
				kills.append(a_occurrence)
	)
	host.garrison.flush(killer)
	assert_eq(kills.size(), 2, "one ON_KILL per occupant")
	assert_gt(killer.veterancy.experience, 0, "and the kill experience")


func test_a_flushed_neutral_building_is_neutral_again() -> void:
	var host: Actor = _held_building(2)
	assert_eq(host.commander_id, HOLDER_ID, "its occupants had adopted it")
	host.garrison.flush()
	assert_eq(host.commander_id, NEUTRAL_ID)


func test_the_dead_take_their_guns_off_the_bunker() -> void:
	var host: Actor = _held_building(1)
	assert_not_null(host.get_node_or_null("Loadout"), "a bunker hoists its occupant's Loadout")
	host.garrison.flush()
	await get_tree().process_frame
	assert_null(host.get_node_or_null("Loadout"))


func test_a_garrison_that_is_not_flushable_cannot_be_flushed() -> void:
	var host: Actor = _held_building(2, false)
	assert_eq(host.garrison.flush(), 0)
	assert_eq(host.garrison.garrisoned_count(), 2)


#endregion


#region A flushing emission
func _shell(a_options: Dictionary, a_flushes: bool) -> Payload:
	var shell: Entity = FakePieces.emission(a_options)
	add_child_autofree(shell)
	var payload: Payload = Payload.of(shell)
	payload.flushes = a_flushes
	return payload


func test_a_shot_landing_on_the_host_flushes_it() -> void:
	var host: Actor = _held_building(2)
	var payload: Payload = _shell({"hitscan": true, "hit_shape": false}, true)
	payload.arm(null, host)
	payload.apply()
	assert_eq(host.garrison.garrisoned_count(), 0)


func test_a_blast_that_strikes_the_host_flushes_it() -> void:
	var host: Actor = _held_building(2)
	var payload: Payload = _shell({}, true)
	(payload.host().get_node("Locomotion") as PhasedLocomotion).struck.emit(host)
	payload.apply()
	assert_eq(host.garrison.garrisoned_count(), 0)


func test_a_blast_that_strikes_something_else_does_not_flush_the_host() -> void:
	# The shell bursts on the host's doorstep: the blast covers the building, but its contact
	# was the soldier outside, so nothing inside is touched.
	var host: Actor = _held_building(2)
	var outside: Actor = _piece(SOLDIER, STORMER_ID)
	var payload: Payload = _shell({}, true)
	payload.host().global_position = host.global_position
	(payload.host().get_node("Locomotion") as PhasedLocomotion).struck.emit(outside)
	payload.apply()
	assert_eq(host.garrison.garrisoned_count(), 2)


func test_a_shot_that_does_not_flush_leaves_the_garrison_alone() -> void:
	var host: Actor = _held_building(2)
	var payload: Payload = _shell({"hitscan": true, "hit_shape": false}, false)
	payload.arm(null, host)
	payload.apply()
	assert_eq(host.garrison.garrisoned_count(), 2)


#endregion


#region Storming
func _order(a_actor: Actor, a_host: Actor) -> MoveCommand.PreconditionFailureCause:
	return Flush.meets_precondition(a_actor, CommandMessage.new(null, a_host))


func test_a_flusher_may_storm_an_enemy_held_flushable_building() -> void:
	var host: Actor = _held_building(2)
	assert_eq(_order(_piece(STORMER, STORMER_ID), host), MoveCommand.PreconditionFailureCause.NONE)


func test_storming_needs_a_flusher_an_enemy_holder_and_a_flushable_host() -> void:
	var none := MoveCommand.PreconditionFailureCause.NONE
	assert_ne(_order(_piece(SOLDIER, STORMER_ID), _held_building(2)), none, "not a flusher")
	assert_ne(_order(_piece(STORMER, HOLDER_ID), _held_building(2)), none, "its own side")
	assert_ne(_order(_piece(STORMER, STORMER_ID), _held_building(0)), none, "empty: Occupy's")
	assert_ne(_order(_piece(STORMER, STORMER_ID), _held_building(2, false)), none, "unflushable")


func test_a_flusher_right_clicking_an_enemy_held_building_storms_rather_than_shoots() -> void:
	var host: Actor = _held_building(2)
	var stormer: Actor = _piece(STORMER.merged({"weapon": {"ground": 6.0}}), STORMER_ID)
	var message := CommandMessage.new(null, host)
	assert_eq(RTSController._resolve_command_class("", stormer, message), Flush)
	var soldier: Actor = _piece(SOLDIER, STORMER_ID)
	assert_eq(RTSController._resolve_command_class("", soldier, message), Attack, "no Flusher")


func test_storming_flushes_the_host_and_enters_it() -> void:
	var host: Actor = _held_building(4)
	var stormer: Actor = _piece(STORMER, STORMER_ID)
	var order := Flush.new(CommandMessage.new(null, host))
	order.fulfill_action(stormer)
	assert_eq(host.garrison.occupants(), [stormer] as Array[Actor], "the place is the stormer's")
	assert_eq(host.commander_id, STORMER_ID)


func test_the_flush_makes_the_room_it_enters() -> void:
	var host: Actor = _held_building(4)
	var stormer: Actor = _piece(STORMER, STORMER_ID)
	stormer.global_position = host.global_position
	var order := Flush.new(CommandMessage.new(null, host))
	assert_false(host.garrison.accepts(stormer), "full")
	assert_true(order.can_act(stormer), "but it is about to be emptied")

#endregion
