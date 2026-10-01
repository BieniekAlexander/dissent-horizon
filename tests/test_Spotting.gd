extends GutTest

## The Spot command's lifecycle — the Colonial artillery's forward-observer half.
##
## The COMMITMENT is the mechanic and most of what is checked here: a spotter walks into
## range, holds still while it calls the strike in, and then STAYS on its beacon until a
## Bombard spends it. Anything queued behind waits for the shot; any new order cancels the
## solution and takes the beacon with it. Each of those is a place the naive
## implementation (end the command when the beacon goes up) would be silently wrong.
##
## Driven by calling the command's hooks directly rather than through a live receiver:
## the state machine consults only the actor's position and its granted ability, so no
## NavigationServer or Map is needed.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_Spotting.gd -gexit

## A piece granted Spot.
const RECRUIT: Dictionary = {"speed": 2.0, "vision": 8.0,
	"abilities": [{"grants": [Spot.ABILITY_ID]}]}

## A Map that answers only the one question _raise_beacon asks. A real one needs a
## heightmap before terrain_height_at means anything, and none of that would make these
## assertions stronger — same fixture idiom as test_CoBuild's StubMap.
class StubMap extends Map:
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
	for _i: int in Spot.CHANNEL_TICKS:
		a_command.fulfill_action(a_actor)
	return a_command._beacon


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


func test_the_reach_is_the_ability_docs_range_and_the_channel_is_ten_seconds() -> void:
	# The reach is read off the spot ability's `range:` (10 in this fixture); the channel is
	# 10 seconds — 30 physics ticks to the second.
	var recruit: Commandable = FakePieces.unit({"abilities": [{"grants": [Spot.ABILITY_ID]}]})
	autofree(recruit)
	assert_almost_eq(Spot.target_range(recruit), 10.0, 0.001)
	assert_eq(Spot.CHANNEL_TICKS, 300)


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
	for _i: int in 299:
		command.fulfill_action(recruit)
	assert_null(command._beacon, "still calling it in at 299 ticks")
	command.fulfill_action(recruit)
	assert_not_null(command._beacon, "and it stands on the 300th")


func test_the_channel_reports_its_progress() -> void:
	var recruit := _recruit(Vector2(0, 0))
	_give_map(recruit)
	var command := _order(Vector2(5, 0))
	assert_almost_eq(command.channel_progress(recruit), 0.0, 0.001)
	for _i: int in 150:
		command.fulfill_action(recruit)
	assert_almost_eq(command.channel_progress(recruit), 0.5, 0.01)
	_channel_out(recruit, command)
	assert_almost_eq(command.channel_progress(recruit), 1.0, 0.001)


func test_the_beacon_stands_where_it_was_ordered() -> void:
	var recruit := _recruit(Vector2(0, 0))
	_give_map(recruit)
	var command := _order(Vector2(5, 3))
	var beacon := _channel_out(recruit, command)
	assert_not_null(beacon)
	assert_almost_eq(VU.inXZ(beacon.host().global_position).distance_to(Vector2(5, 3)), 0.0, 0.001)


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


func test_it_finishes_when_the_beacon_is_spent() -> void:
	var recruit := _recruit(Vector2(0, 0))
	_give_map(recruit)
	var command := _order(Vector2(5, 0))
	var beacon := _channel_out(recruit, command)
	beacon.dismiss()
	beacon.host().free()   # queue_free is end-of-frame; the command tests validity
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
