extends GutTest

## Automatic fire: a spotter holding a beacon calls its own shot from the nearest of its side's
## Bombards that is loaded, while its commander has the Bombard on automatic; and the right-click
## toggle, a commander-wide setting, that switches it to manual.
## Rules: gdd/systems/combat/bombardment.md §Automatic fire.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_BombardAutofire.gd -gexit

const OWN: int = 1
const FOE: int = 2

const SPOTTER: Dictionary = {"speed": 2.0, "vision": 8.0, "abilities": [{"grants": [&"spot"]}]}


## Answers the one map question beacon placement asks.
class StubMap:
	extends Map

	func terrain_height_at(_a_world_xz: Vector2) -> float:
		return 0.0


var _commanders: Dictionary = {}
var _map: Map


func before_each() -> void:
	FakePieces.install_emitting_ability(Bombard.ABILITY_ID, {"range": 100.0})
	FakePieces.install_ability(&"spot", {"range": 30.0})
	_commanders = {}
	_map = StubMap.new()


func after_each() -> void:
	FakePieces.restore_abilities()
	if is_instance_valid(_map):
		_map.free()
	_map = null


func _commander(a_id: int) -> Commander:
	if not _commanders.has(a_id):
		var commander := Commander.new()
		commander.id = a_id
		add_child_autofree(commander)
		commander.add_infrastructure(1000)
		_commanders[a_id] = commander
	return _commanders[a_id]


func _at(a_xz: Vector2) -> Vector3:
	return Vector3(a_xz.x, 0.0, a_xz.y)


func _piece(a_options: Dictionary, a_commander_id: int, a_xz: Vector2) -> Commandable:
	var piece: Commandable = FakePieces.make(a_options)
	_commander(a_commander_id).add_child(piece)
	autofree(piece)
	piece.top_level = true
	piece.ownership.commander = _commander(a_commander_id)
	piece.global_position = _at(a_xz)
	piece.map = _map
	return piece


## A finished, loaded gun. No BeaconRange, so only a beacon spots for it.
func _gun(a_xz: Vector2, a_commander_id: int = OWN) -> Commandable:
	var gun := _piece(
		{
			"structure": true,
			"dimensions": Vector2i(2, 2),
			"abilities": [{"grants": [Bombard.ABILITY_ID]}]
		},
		a_commander_id,
		a_xz
	)
	gun.build_progress = 1.0
	return gun


func _pool(a_piece: Commandable) -> Abilities:
	return a_piece.get_node("Abilities") as Abilities


## A spotter that has called in a beacon at `a_xz` and is holding it.
func _holding_spotter(a_xz: Vector2) -> Array:
	var spotter := _piece(SPOTTER, OWN, a_xz)
	var order := Spot.new(CommandMessage.new(null, null, null, _at(a_xz)))
	for _i: int in Spot.channel_ticks():
		order.fulfill_action(spotter)
	return [spotter, order]


func test_a_holding_spotter_fires_the_nearest_loaded_gun() -> void:
	var near := _gun(Vector2(50, 0))
	var far := _gun(Vector2(-50, 0))
	var held: Array = _holding_spotter(Vector2(80, 0))
	var order: Spot = held[1]
	var beacon: Beacon = order._beacon
	assert_false(beacon.is_used(), "the call itself fires nothing")
	order.fulfill_action(held[0])
	assert_true(beacon.is_used(), "the next tick of holding calls the shot")
	assert_false(_pool(near).is_ready(Bombard.ABILITY_ID), "from the nearer gun")
	assert_true(_pool(far).is_ready(Bombard.ABILITY_ID))
	assert_null(order.get_updated_state(held[0]), "and the shot releases the spotter")


func test_it_waits_for_a_gun_to_load() -> void:
	var gun := _gun(Vector2(50, 0))
	_pool(gun).spend(Bombard.ABILITY_ID)
	var held: Array = _holding_spotter(Vector2(80, 0))
	var order: Spot = held[1]
	order.fulfill_action(held[0])
	assert_false(order._beacon.is_used(), "nothing loaded")
	_pool(gun)._charges[0] = 1
	order.fulfill_action(held[0])
	assert_true(order._beacon.is_used(), "fired the tick a gun is ready")


func test_a_commander_on_manual_fires_nothing_on_its_own() -> void:
	var gun := _gun(Vector2(50, 0))
	_commander(OWN).set_autocast(Bombard.ABILITY_ID, false)
	var held: Array = _holding_spotter(Vector2(80, 0))
	held[1].fulfill_action(held[0])
	assert_false(held[1]._beacon.is_used(), "every gun waits for an order")
	assert_true(_pool(gun).is_ready(Bombard.ABILITY_ID))
	_commander(OWN).set_autocast(Bombard.ABILITY_ID, true)
	held[1].fulfill_action(held[0])
	assert_true(held[1]._beacon.is_used(), "and fires again once switched back")


func test_a_gun_holding_a_players_order_is_not_taken() -> void:
	var gun := _gun(Vector2(50, 0))
	var orders: Array[MoveCommand] = [
		Bombard.new(CommandMessage.new(null, null, null, _at(Vector2(200, 0))))
	]
	gun.command_receiver._command_queue = orders
	assert_false(Bombard.can_autofire(gun))


func test_an_unfinished_or_stunned_gun_is_passed_over() -> void:
	var unfinished := _gun(Vector2(50, 0))
	unfinished.build_progress = 0.5
	assert_false(Bombard.can_autofire(unfinished), "unfinished")
	var stunned := _gun(Vector2(60, 0))
	assert_true(Bombard.can_autofire(stunned), "a loaded gun may")
	var stun := StunStatusEffect.new()
	stun.affects_frames = Garrison.FRAME_ANY
	stun.apply_to(stunned)
	assert_true(stunned.is_stunned(), "fixture: the stun took")
	assert_false(Bombard.can_autofire(stunned), "stunned")


func test_another_sides_guns_never_answer() -> void:
	_gun(Vector2(50, 0), FOE)
	var held: Array = _holding_spotter(Vector2(80, 0))
	held[1].fulfill_action(held[0])
	assert_false(held[1]._beacon.is_used())


func test_one_ready_gun_answers_one_beacon() -> void:
	_gun(Vector2(0, 0))
	var first: Array = _holding_spotter(Vector2(40, 0))
	var second: Array = _holding_spotter(Vector2(-40, 0))
	first[1].fulfill_action(first[0])
	second[1].fulfill_action(second[0])
	assert_ne(first[1]._beacon.is_used(), second[1]._beacon.is_used(), "exactly one is fired on")


# --- The toggle ----------------------------------------------------------------------


func test_automatic_is_the_default() -> void:
	assert_true(_commander(OWN).is_autocasting(Bombard.ABILITY_ID))


func test_the_setting_is_the_commanders_not_a_guns() -> void:
	_gun(Vector2(50, 0))
	_commander(OWN).toggle_autocast(Bombard.ABILITY_ID)
	assert_false(_commander(OWN).is_autocasting(Bombard.ABILITY_ID))
	assert_true(_commander(FOE).is_autocasting(Bombard.ABILITY_ID), "another side's is its own")
	_commander(OWN).toggle_autocast(Bombard.ABILITY_ID)
	assert_true(_commander(OWN).is_autocasting(Bombard.ABILITY_ID))


func test_the_button_is_lit_while_the_commander_is_on_automatic() -> void:
	var gun := _gun(Vector2(50, 0))
	assert_true(
		CommandButtonState.of("command_bombard", [gun], _commander(OWN), false).is_toggled_on
	)
	_commander(OWN).set_autocast(Bombard.ABILITY_ID, false)
	assert_false(
		CommandButtonState.of("command_bombard", [gun], _commander(OWN), false).is_toggled_on
	)


## A controller under a commander of its own, as the player's rig has it. Both stay OUT of
## the tree: the controller's _ready builds the whole HUD, and the toggle needs none of it.
func _controller() -> RTSController:
	var commander := Commander.new()
	commander.id = OWN
	var controller := RTSController.new()
	commander.add_child(controller)
	autofree(commander)
	return controller


func _right_click() -> InputEventMouseButton:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_RIGHT
	click.pressed = true
	return click


func test_right_clicking_the_command_card_button_toggles_it() -> void:
	var controller := _controller()
	var button := ButtonSpec.create_button_from_spec(
		ButtonSpec.new("command_bombard", "Bombard", "tip")
	)
	controller.add_child(button)
	button.gui_input.emit(_right_click())
	assert_false((controller.get_parent() as Commander).is_autocasting(Bombard.ABILITY_ID))


func test_right_clicking_spots_button_toggles_it_too() -> void:
	# Spot is the order whose beacon the guns answer, and a Recruit's card has no Bombard on it.
	var controller := _controller()
	var button := ButtonSpec.create_button_from_spec(ButtonSpec.new("command_spot", "Spot", "tip"))
	controller.add_child(button)
	button.gui_input.emit(_right_click())
	assert_false((controller.get_parent() as Commander).is_autocasting(Bombard.ABILITY_ID))


func test_spots_button_is_lit_while_the_commander_is_on_automatic() -> void:
	var recruit := _piece(SPOTTER, OWN, Vector2.ZERO)
	assert_true(
		CommandButtonState.of("command_spot", [recruit], _commander(OWN), false).is_toggled_on
	)
	_commander(OWN).set_autocast(Bombard.ABILITY_ID, false)
	assert_false(
		CommandButtonState.of("command_spot", [recruit], _commander(OWN), false).is_toggled_on
	)


func test_right_clicking_the_hud_bar_button_toggles_it() -> void:
	var controller := _controller()
	var button := VerboseTooltipButton.new()
	controller.add_child(button)
	controller._on_deploy_button_input(_right_click(), button, Bombard.ABILITY_ID)
	assert_false((controller.get_parent() as Commander).is_autocasting(Bombard.ABILITY_ID))
