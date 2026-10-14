extends GutTest

## A player's order shows where it sends its units the moment it is given, before the order stream
## applies it — so input delay is never seen on a click — and from then on its waypoints are read
## off the units' own commands each frame; nothing is drawn by the apply itself.
## gdd/systems/commands/netplay.md §Decisions (order feedback).

## Where every test's order points.
const DESTINATION: Vector3 = Vector3(5.0, 0.0, 3.0)
## How close a drawn waypoint must sit to where the order sends its unit, on flat ground.
const PLACE_TOLERANCE: float = 0.01


## A controller whose commander is named rather than found: the real one needs the tree, and
## entering it builds the whole HUD.
class Controller:
	extends RTSController
	var owner_commander: Commander

	func _commander() -> Commander:
		return owner_commander


var _map: Map
var _controller: Controller
var _unit: Actor
var _player: Commander


func before_each() -> void:
	_map = SimArena.flat_map(16)
	add_child_autofree(_map)
	_player = Commander.new()
	_player.id = 1
	add_child_autofree(_player)
	_controller = autofree(Controller.new()) as Controller
	_controller.owner_commander = _player
	_controller.map = _map
	_unit = _owned_unit(_player)
	_controller.selection.assign([_unit])


func _owned_unit(a_owner: Commander) -> Actor:
	var unit: Actor = FakePieces.unit({"speed": 2.0}) as Actor
	add_child_autofree(unit)
	unit.ownership.commander = a_owner
	return unit


func _message() -> CommandMessage:
	return CommandMessage.new(_map, null, null, DESTINATION)


func _visible_indicators() -> Array:
	return _controller._indicator_pool.filter(func(i: WaypointIndicator) -> bool: return i.visible)


func test_the_dispatcher_marks_a_placed_message_for_a_waypoint() -> void:
	var placed: Array = OrderDispatcher.apply_command(_map, MoveCommand, [_unit], _message(), {})
	assert_eq(placed.size(), 1)
	assert_true((placed[0] as CommandMessage).shows_waypoint)
	assert_true(_unit.current_command().message.shows_waypoint, "on the unit's own command")


func test_an_applied_order_is_drawn_from_the_units_command_alone() -> void:
	OrderDispatcher.apply_command(_map, MoveCommand, [_unit], _message(), {})
	_controller._update_waypoint_display()
	assert_eq(_visible_indicators().size(), 1, "read off the command, nothing registered")


func test_a_given_order_is_drawn_before_it_is_applied() -> void:
	var order: PlayerOrder = PlayerOrder.command(1, MoveCommand, [_unit], _message(), {})
	_controller._preview_order(order, MoveCommand, _message(), {})
	_controller._update_waypoint_display()
	var shown: Array = _visible_indicators()
	assert_eq(shown.size(), 1, "the moment it is given")
	assert_eq(_unit.current_command(), null, "and nothing has been applied")


func test_the_preview_gives_way_once_the_order_is_applied() -> void:
	var order: PlayerOrder = PlayerOrder.command(1, MoveCommand, [_unit], _message(), {})
	_controller._preview_order(order, MoveCommand, _message(), {})
	# As the stream hands it back in a networked match: the copy decoded off the wire, ticked.
	var applied: PlayerOrder = PlayerOrder.from_dict(
		JSON.parse_string(JSON.stringify(order.to_dict()))
	)
	applied.tick = 9
	_controller._drop_preview(applied)
	_controller._update_waypoint_display()
	assert_eq(_visible_indicators().size(), 0, "the preview is gone, and nothing was applied here")


func test_an_order_without_a_place_draws_no_preview() -> void:
	var order := PlayerOrder.new(PlayerOrder.Kind.COMMAND, 1, {})
	_controller._preview_order(order, Stop, _message(), {})
	assert_eq(_controller._order_previews.size(), 0)


func test_another_players_unit_shows_none_of_its_waypoints() -> void:
	var rival := Commander.new()
	rival.id = 2
	add_child_autofree(rival)
	var theirs: Actor = _owned_unit(rival)
	OrderDispatcher.apply_command(_map, MoveCommand, [theirs], _message(), {})
	_controller.selection.assign([theirs])
	_controller._update_waypoint_display()
	assert_eq(_visible_indicators().size(), 0, "where a rival sent its unit stays hidden")
