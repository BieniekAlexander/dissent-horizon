extends GutTest

## A called-in aircraft's sortie: in with its guns cold, on station circling a point and taking
## only orders to shoot from it, then home past its entry point and gone.
## Rules: gdd/systems/macroeconomics/sanctions/off-map-abilities.md §Gunship.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_Sortie.gd -gexit


class FakeMap:
	extends Map
	var area: PlayArea = null

	func play_area() -> PlayArea:
		return area

	func terrain_height_at(_a_world_xz: Vector2) -> float:
		return 0.0


const HALF: Vector2 = Vector2(20.0, 20.0)
const STATION: Vector3 = Vector3(5.0, 0.0, 0.0)
## Just outside the play area's edge, where an entry point stands.
const HOME: Vector3 = Vector3(-30.0, 0.0, 0.0)
const STATION_SECONDS: float = 1.0
const GUNSHIP: Dictionary = {"aerial": true, "flying": true, "weapon": {"ground": 6.0}}

var _map: FakeMap


func before_each() -> void:
	_map = autofree(FakeMap.new())
	_map.area = PlayArea.axis_aligned(Vector2.ZERO, HALF)


func _launch(a_at: Vector3 = HOME) -> Array:
	var aircraft: Commandable = FakePieces.unit(GUNSHIP)
	add_child_autofree(aircraft)
	aircraft.global_position = a_at
	var sortie: Sortie = Sortie.launch(aircraft, _map, HOME, STATION, STATION_SECONDS)
	# Ticked by hand, one call per physics tick.
	sortie.set_physics_process(false)
	return [aircraft, sortie]


## Move the aircraft over the station and let the sortie see it arrive.
func _on_station() -> Array:
	var flown: Array = _launch()
	flown[0].global_position = STATION
	flown[1]._physics_process(0.0)
	return flown


func _move_order() -> MoveCommand:
	return MoveCommand.new(CommandMessage.new(_map, null, null, Vector3(10.0, 0.0, 10.0)))


func _attack_order() -> Attack:
	var target: Commandable = FakePieces.unit({"speed": 2.0})
	add_child_autofree(target)
	return Attack.new(CommandMessage.new(_map, target, null))


func test_it_flies_in_with_its_guns_cold() -> void:
	var flown: Array = _launch()
	assert_true(flown[0].current_command() is SortieLeg)
	assert_eq(flown[0].current_command().message.position, STATION)
	assert_false(flown[0].can_use_weapons())


func test_in_transit_it_takes_no_order_at_all() -> void:
	var flown: Array = _launch()
	flown[0].update_commands(_attack_order())
	assert_true(flown[0].current_command() is SortieLeg, "not even an Attack")


func test_a_cleared_leg_is_flown_again() -> void:
	var flown: Array = _launch()
	flown[0].update_commands(null)
	flown[1]._physics_process(0.0)
	assert_true(flown[0].current_command() is SortieLeg)


func test_over_the_station_its_guns_go_live() -> void:
	var flown: Array = _on_station()
	assert_eq(flown[1].phase, Sortie.Phase.ON_STATION)
	assert_null(flown[0].current_command(), "the leg is over")
	assert_true(flown[0].can_use_weapons())


func test_on_station_it_takes_an_attack_but_never_a_move() -> void:
	var flown: Array = _on_station()
	flown[0].update_commands(_move_order())
	assert_null(flown[0].current_command(), "a move is refused")
	flown[0].update_commands(_attack_order())
	assert_true(flown[0].current_command() is Attack)


func test_idle_on_station_it_circles_the_station() -> void:
	var flown: Array = _on_station()
	flown[0].aerial.set_anchor(Vector3(12.0, 0.0, 3.0))
	flown[1]._physics_process(0.0)
	assert_eq(flown[0].aerial.anchor(), STATION)


func test_when_its_time_is_up_it_goes_home_cold() -> void:
	var flown: Array = _on_station()
	flown[0].update_commands(_attack_order())
	for _i: int in TimeUtils.ticks_from_seconds(STATION_SECONDS):
		flown[1]._physics_process(0.0)
	assert_eq(flown[1].phase, Sortie.Phase.OUTBOUND)
	assert_false(flown[0].can_use_weapons())
	var leg: MoveCommand = flown[0].current_command()
	assert_true(leg is SortieLeg, "the attack is dropped for the way home")
	assert_lt(leg.message.position.x, HOME.x, "out past the edge it came in over")


func test_off_the_board_it_is_gone() -> void:
	var flown: Array = _on_station()
	flown[1].phase = Sortie.Phase.OUTBOUND
	flown[1]._physics_process(0.0)
	assert_false(flown[0].is_queued_for_deletion(), "still over the board")
	flown[0].global_position = HOME + Vector3(-1.0, 0.0, 0.0)
	flown[1]._physics_process(0.0)
	assert_true(flown[0].is_queued_for_deletion())


func test_its_card_offers_attack_but_nothing_that_moves_it() -> void:
	var flown: Array = _launch()
	var offered: Array = CommandContextParser.commands_for(flown[0])
	assert_has(offered, "command_attack")
	assert_has(offered, "command_attack_move", "the button that attacks a target it is hovering")
	for refused: String in ["command_move", "command_patrol", "command_defend"]:
		assert_does_not_have(offered, refused)


func test_attack_move_on_ground_is_refused_but_on_a_target_is_an_attack() -> void:
	var flown: Array = _on_station()
	var ground := CommandMessage.new(_map, null, null, Vector3(10.0, 0.0, 10.0))
	assert_ne(
		AttackMove.meets_precondition(flown[0], ground), MoveCommand.PreconditionFailureCause.NONE
	)
	var target: Attack = _attack_order()
	assert_eq(RTSController._resolve_hotkey_command("command_attack_move", target.message), Attack)
	assert_eq(
		Attack.meets_precondition(flown[0], target.message),
		MoveCommand.PreconditionFailureCause.NONE
	)


func test_a_piece_off_rails_may_still_attack_move() -> void:
	var aircraft: Commandable = FakePieces.unit(GUNSHIP)
	add_child_autofree(aircraft)
	var ground := CommandMessage.new(_map, null, null, Vector3(10.0, 0.0, 10.0))
	assert_eq(
		AttackMove.meets_precondition(aircraft, ground), MoveCommand.PreconditionFailureCause.NONE
	)


func test_an_aircraft_without_a_sortie_is_offered_a_move() -> void:
	var aircraft: Commandable = FakePieces.unit(GUNSHIP)
	add_child_autofree(aircraft)
	assert_has(CommandContextParser.commands_for(aircraft), "command_move")
