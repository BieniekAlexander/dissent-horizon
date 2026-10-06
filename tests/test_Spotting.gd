extends GutTest

## The Spot command's lifecycle — the Colonial artillery's forward-observer half.
##
## The COMMITMENT is the mechanic and most of what is checked here: a spotter walks into
## range, holds still while it calls the strike in, and then STAYS on its beacon until a
## Bombard fires on it. Anything queued behind waits for the shot; any new order cancels
## the solution and takes the beacon with it, and the cooldown runs from whenever the order
## ends. Each of those is a place the naive
## implementation (end the command when the beacon goes up) would be silently wrong.
##
## Driven by calling the command's hooks directly rather than through a live receiver:
## the state machine consults only the actor's position and its granted ability, so no
## NavigationServer or Map is needed.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_Spotting.gd -gexit

## The spotter's cooldown in this fixture, in ticks.
const COOLDOWN_TICKS: int = 450

## A piece granted Spot.
const RECRUIT: Dictionary = {
	"speed": 2.0,
	"vision": 8.0,
	"abilities": [{"grants": [Spot.ABILITY_ID], "cooldown_ticks": COOLDOWN_TICKS}]
}


## A Map that answers only the one question _raise_beacon asks. A real one needs a
## heightmap before terrain_height_at means anything, and none of that would make these
## assertions stronger — same fixture idiom as test_CoBuild's StubMap.
class StubMap:
	extends Map

	func terrain_height_at(_a_world_xz: Vector2) -> float:
		return 0.0


var _commander: Commander
var _map: Map


func before_each() -> void:
	FakePieces.install_ability(Spot.ABILITY_ID, {"range": 10.0, "command": "command_spot"})
	_commander = Commander.new()
	_commander.id = 1
	add_child_autofree(_commander)


func after_each() -> void:
	FakePieces.restore_abilities()
	if _map != null and is_instance_valid(_map):
		_map.free()
		_map = null


## A unit granted Spot.
func _recruit(a_at: Vector2 = Vector2.ZERO) -> Commandable:
	var unit: Commandable = FakePieces.make(RECRUIT)
	_commander.add_child(unit)
	autofree(unit)
	unit.top_level = true
	unit.ownership.commander = _commander
	unit.global_position = Vector3(a_at.x, 0.0, a_at.y)
	return unit


## A Spot order aimed at `target`. The message carries no Map; _raise_beacon falls back to
## the actor's, which the fixture supplies below.
func _order(a_target: Vector2) -> Spot:
	return Spot.new(CommandMessage.new(null, null, null, Vector3(a_target.x, 0.0, a_target.y)))


## Give the actor a Map so a beacon has somewhere to be placed. Minimal: _raise_beacon
## reads only terrain_height_at.
func _give_map(a_actor: Commandable) -> void:
	if _map == null:
		_map = StubMap.new()
	a_actor.map = _map


## Run the channel to completion, returning the beacon it raised.
func _channel_out(a_actor: Commandable, a_command: Spot) -> Beacon:
	for _i: int in Spot.channel_ticks():
		a_command.fulfill_action(a_actor)
	return a_command._beacon


## The spotter's ability pool.
func _pool(a_actor: Commandable) -> Abilities:
	return a_actor.get_node("Abilities") as Abilities


## Tick `a_actor`'s ability pool `a_ticks` times.
func _recharge(a_actor: Commandable, a_ticks: int) -> void:
	for _i: int in a_ticks:
		_pool(a_actor)._physics_process(0.0)


# --- Capability ------------------------------------------------------------------


func test_the_recruit_is_a_spotter() -> void:
	var recruit := _recruit()
	var pool := recruit.get_node_or_null("Abilities") as Abilities
	assert_not_null(pool, "carries an ability pool")
	assert_true(pool.grants(Spot.ABILITY_ID), "and is granted Spot")
	assert_eq(Spot.meets_precondition(recruit, null), MoveCommand.PreconditionFailureCause.NONE)
	assert_true(CommandContextParser.commands_for(recruit).has("command_spot"))


func test_a_unit_without_the_component_cannot_spot() -> void:
	var badger: Commandable = FakePieces.unit({"speed": 2.0, "weapon": {"ground": 6.0}})
	autofree(badger)
	assert_ne(Spot.meets_precondition(badger, null), MoveCommand.PreconditionFailureCause.NONE)
	assert_false(CommandContextParser.commands_for(badger).has("command_spot"))


func test_the_reach_is_the_ability_docs_range_and_the_channel_is_in_seconds() -> void:
	# The reach is read off the spot ability's `range:` (10 in this fixture); the channel is
	# authored in seconds and counted in ticks.
	var recruit: Commandable = FakePieces.unit({"abilities": [{"grants": [Spot.ABILITY_ID]}]})
	autofree(recruit)
	assert_almost_eq(Spot.target_range(recruit), 10.0, 0.001)
	assert_eq(Spot.channel_ticks(), TimeUtils.ticks_from_seconds(Spot.CHANNEL_SECONDS))


# --- Approach --------------------------------------------------------------------


func test_it_walks_until_it_is_in_range() -> void:
	var recruit := _recruit(Vector2(0, 0))
	var command := _order(Vector2(40, 0))
	assert_false(command.can_act(recruit), "40 units away is out of reach")
	assert_true(command.should_move(recruit), "so it walks")


func test_it_stops_and_calls_once_within_range() -> void:
	var recruit := _recruit(Vector2(0, 0))
	var command := _order(Vector2(9, 0))
	assert_true(command.can_act(recruit), "inside the 10-unit reach")
	assert_false(command.should_move(recruit))


func test_arriving_does_not_end_the_order() -> void:
	# The same override Build and Assemble need: arriving is where the work STARTS, and
	# without it the receiver drops the order the moment the unit stops walking.
	assert_false(_order(Vector2.ZERO).ends_on_arrival())


# --- The channel -----------------------------------------------------------------


func test_the_beacon_only_appears_after_the_full_channel() -> void:
	var recruit := _recruit(Vector2(0, 0))
	_give_map(recruit)
	var command := _order(Vector2(5, 0))
	for _i: int in Spot.channel_ticks() - 1:
		command.fulfill_action(recruit)
	assert_null(command._beacon, "still calling it in one tick short")
	command.fulfill_action(recruit)
	assert_not_null(command._beacon, "and it stands on the last tick")


func test_the_channel_reports_its_progress() -> void:
	var recruit := _recruit(Vector2(0, 0))
	_give_map(recruit)
	var command := _order(Vector2(5, 0))
	assert_almost_eq(command.channel_progress(recruit), 0.0, 0.001)
	for _i: int in Spot.channel_ticks() / 2:
		command.fulfill_action(recruit)
	assert_almost_eq(command.channel_progress(recruit), 0.5, 0.02)
	_channel_out(recruit, command)
	assert_almost_eq(command.channel_progress(recruit), 1.0, 0.001)


func test_the_beacon_stands_where_it_was_ordered() -> void:
	var recruit := _recruit(Vector2(0, 0))
	_give_map(recruit)
	var command := _order(Vector2(5, 3))
	var beacon := _channel_out(recruit, command)
	assert_not_null(beacon)
	assert_almost_eq(VU.in_xz(beacon.host().global_position).distance_to(Vector2(5, 3)), 0.0, 0.001)


func test_the_spotters_beacon_never_expires_on_its_own() -> void:
	# Its lifetime is the spotter's commitment, not a timer's.
	var recruit := _recruit(Vector2(0, 0))
	_give_map(recruit)
	var beacon := _channel_out(recruit, _order(Vector2(5, 0)))
	assert_null(beacon.host().get_node_or_null("Lifespan"), "no Lifespan: it stands until spent")


# --- The hold --------------------------------------------------------------------


func test_it_does_not_finish_when_the_beacon_goes_up() -> void:
	# The commitment: a command that ended here would let the unit walk on to its next
	# queued order while its solution still stood.
	var recruit := _recruit(Vector2(0, 0))
	_give_map(recruit)
	var command := _order(Vector2(5, 0))
	_channel_out(recruit, command)
	assert_eq(command.get_updated_state(recruit), command, "the order is still live")
	assert_false(command.should_move(recruit), "and holds the unit in place")


func test_it_finishes_when_a_bombard_fires_on_the_beacon() -> void:
	# Fired on, not landed: the spotter is free the moment the shot is away, and the beacon
	# stands for the shell that is tracking it.
	var recruit := _recruit(Vector2(0, 0))
	_give_map(recruit)
	var command := _order(Vector2(5, 0))
	var beacon := _channel_out(recruit, command)
	beacon.mark_used()
	assert_null(command.get_updated_state(recruit), "the order ends with the shot")
	command.on_released(recruit)
	assert_false(beacon.host().is_queued_for_deletion(), "the fired-on beacon stays for the shell")


func test_it_finishes_when_the_beacon_is_spent() -> void:
	var recruit := _recruit(Vector2(0, 0))
	_give_map(recruit)
	var command := _order(Vector2(5, 0))
	var beacon := _channel_out(recruit, command)
	beacon.dismiss()
	beacon.host().free()  # queue_free is end-of-frame; the command tests validity
	assert_null(command.get_updated_state(recruit), "the order ends with the shot")


func test_being_re_ordered_takes_the_beacon_with_it() -> void:
	# A solution belongs to the unit holding it. Leaving one behind would let a player
	# place beacons for free by re-tasking the spotter.
	var recruit := _recruit(Vector2(0, 0))
	_give_map(recruit)
	var command := _order(Vector2(5, 0))
	var beacon := _channel_out(recruit, command)
	assert_false(beacon.host().is_queued_for_deletion())
	command.on_released(recruit)
	assert_true(beacon.host().is_queued_for_deletion(), "the solution is withdrawn")


func test_releasing_before_the_beacon_is_up_is_harmless() -> void:
	var recruit := _recruit(Vector2(0, 0))
	_give_map(recruit)
	var command := _order(Vector2(5, 0))
	command.fulfill_action(recruit)
	command.on_released(recruit)
	assert_null(command._beacon)


func test_the_spotters_death_takes_an_unfired_beacon_with_it() -> void:
	var recruit := _recruit(Vector2(0, 0))
	_give_map(recruit)
	var beacon := _channel_out(recruit, _order(Vector2(5, 0)))
	recruit.entity_occurrence.emit(Entity.EntityOccurrence.ON_DEATH, null)
	assert_true(beacon.host().is_queued_for_deletion())


func test_the_spotters_death_leaves_a_fired_on_beacon_for_the_shell() -> void:
	var recruit := _recruit(Vector2(0, 0))
	_give_map(recruit)
	var beacon := _channel_out(recruit, _order(Vector2(5, 0)))
	beacon.mark_used()
	recruit.entity_occurrence.emit(Entity.EntityOccurrence.ON_DEATH, null)
	assert_false(beacon.host().is_queued_for_deletion())


# --- The cooldown ----------------------------------------------------------------


func test_walking_to_the_point_costs_no_charge() -> void:
	var recruit := _recruit(Vector2(0, 0))
	var command := _order(Vector2(40, 0))
	command.on_released(recruit)
	assert_true(_pool(recruit).is_ready(Spot.ABILITY_ID), "abandoned before the channel started")


func test_the_charge_is_spent_when_the_channel_starts() -> void:
	var recruit := _recruit(Vector2(0, 0))
	_give_map(recruit)
	var command := _order(Vector2(5, 0))
	command.fulfill_action(recruit)
	assert_false(_pool(recruit).is_ready(Spot.ABILITY_ID))
	assert_eq(
		Spot.meets_precondition(recruit, null),
		MoveCommand.PreconditionFailureCause.ABILITY_NO_CHARGES,
		"a second solution waits for the cooldown"
	)


func test_the_cooldown_does_not_run_while_the_solution_is_held() -> void:
	var recruit := _recruit(Vector2(0, 0))
	_give_map(recruit)
	_channel_out(recruit, _order(Vector2(5, 0)))
	_recharge(recruit, COOLDOWN_TICKS * 2)
	assert_false(_pool(recruit).is_ready(Spot.ABILITY_ID))


func test_the_cooldown_runs_from_the_end_of_the_order() -> void:
	var recruit := _recruit(Vector2(0, 0))
	_give_map(recruit)
	var command := _order(Vector2(5, 0))
	_channel_out(recruit, command)
	_recharge(recruit, COOLDOWN_TICKS)
	command.on_released(recruit)
	_recharge(recruit, COOLDOWN_TICKS - 1)
	assert_false(_pool(recruit).is_ready(Spot.ABILITY_ID), "one tick short of the full cooldown")
	_recharge(recruit, 1)
	assert_true(_pool(recruit).is_ready(Spot.ABILITY_ID))


func test_cancelling_mid_channel_starts_the_cooldown_too() -> void:
	var recruit := _recruit(Vector2(0, 0))
	_give_map(recruit)
	var command := _order(Vector2(5, 0))
	command.fulfill_action(recruit)
	command.on_released(recruit)
	_recharge(recruit, COOLDOWN_TICKS)
	assert_true(_pool(recruit).is_ready(Spot.ABILITY_ID))


# --- Who is sent --------------------------------------------------------------------


func _narrowed(a_recruits: Array, a_target: Vector2) -> Array:
	var controller: RTSController = autofree(RTSController.new())
	return controller._narrowed_actors(Spot, a_recruits, _order(a_target).message)


func test_one_recruit_is_sent_the_nearest() -> void:
	var near := _recruit(Vector2(10, 0))
	var far := _recruit(Vector2(30, 0))
	assert_eq(_narrowed([far, near], Vector2(0, 0)), [near])


func test_a_recruit_already_spotting_is_passed_over() -> void:
	var near := _recruit(Vector2(10, 0))
	var far := _recruit(Vector2(30, 0))
	near.update_commands(_order(Vector2(40, 40)))
	assert_eq(_narrowed([near, far], Vector2(0, 0)), [far])


func test_a_busy_recruit_that_is_not_spotting_still_counts_as_free() -> void:
	var near := _recruit(Vector2(10, 0))
	var far := _recruit(Vector2(30, 0))
	near.update_commands(MoveCommand.new(CommandMessage.new(null, null, null, Vector3(5, 0, 5))))
	assert_eq(_narrowed([near, far], Vector2(0, 0)), [near])


func test_when_every_recruit_is_spotting_the_nearest_goes() -> void:
	var near := _recruit(Vector2(10, 0))
	var far := _recruit(Vector2(30, 0))
	near.update_commands(_order(Vector2(40, 40)))
	far.update_commands(_order(Vector2(40, 40)))
	assert_eq(_narrowed([far, near], Vector2(0, 0)), [near])


# --- A planter plants and leaves ----------------------------------------------------


## A unit granted Spot that PLANTS its beacon (the Sleeper's way).
func _planter(a_at: Vector2 = Vector2.ZERO) -> Commandable:
	var unit := _recruit(a_at)
	var planter := BeaconPlanter.new()
	planter.name = "BeaconPlanter"
	unit.add_child(planter)
	_give_map(unit)
	return unit


func _beacons() -> Array:
	return get_tree().get_nodes_in_group(Beacon.GROUP).map(
		func(n: Node) -> Beacon: return Beacon.of(n)
	)


func test_a_planter_walks_to_the_point_itself() -> void:
	var planter := _planter(Vector2(0, 0))
	var command := _order(Vector2(5, 0))
	assert_false(command.can_act(planter), "5 units off is inside Spot's range, but not there")
	assert_eq(command.movement_destination(planter), Vector3(5, 0, 0))
	planter.global_position = Vector3(5, 0, 0)
	assert_true(command.can_act(planter))


func test_a_planter_plants_a_ground_beacon_and_the_order_ends() -> void:
	var planter := _planter(Vector2(5, 0))
	var command := _order(Vector2(5, 0))
	var result: Variant = null
	for _i: int in Spot.channel_ticks():
		result = command.fulfill_action(planter)
	assert_null(result, "planted: the order is done")
	var beacons := _beacons()
	assert_eq(beacons.size(), 1)
	var beacon: Beacon = beacons[0]
	assert_almost_eq(VU.in_xz(beacon.host().global_position), Vector2(5, 0), Vector2.ONE * 0.01)
	command.on_released(planter)
	assert_false(beacon.is_leaving(), "nothing holds it, so leaving does not withdraw it")
	assert_false(_pool(planter).is_recharge_held(Spot.ABILITY_ID), "its cooldown runs now")
	for beacon_node: Node in get_tree().get_nodes_in_group(Beacon.GROUP):
		beacon_node.free()


func test_aimed_over_a_vehicle_a_planter_plants_on_the_ground_beneath() -> void:
	var planter := _planter(Vector2(5, 0))
	var vehicle: Commandable = FakePieces.make(FakePieces.MACHINE)
	var foe := Commander.new()
	foe.id = 2
	add_child_autofree(foe)
	foe.add_child(vehicle)
	autofree(vehicle)
	vehicle.top_level = true
	vehicle.ownership.commander = foe
	vehicle.global_position = Vector3(5, 0, 0)
	var command := Spot.new(CommandMessage.new(null, vehicle, null, Vector3(5, 0, 0)))
	for _i: int in Spot.channel_ticks():
		command.fulfill_action(planter)
	var beacons := _beacons()
	assert_eq(beacons.size(), 1)
	assert_null((beacons[0] as Beacon).carrier(), "a point beacon, like a Beacon Drop's")
	for beacon_node: Node in get_tree().get_nodes_in_group(Beacon.GROUP):
		beacon_node.free()
