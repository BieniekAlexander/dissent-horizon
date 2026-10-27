extends GutTest

## A HOVERING unit told to move and then land sets down at the move's goal (Alex, 2026-10-18).
## Two bugs this guards:
## - the move before a queued Land passed through its goal at full speed (an order queued after
##   it made it PASS_THROUGH), and the landing then predicted a touchdown where that speed would
##   carry it over the whole descent — 30-odd units on, often off the map — and chased it;
## - the Land button went for good the moment a Land was given, though the unit had not begun to
##   come down, so a landing that never happened could not be ordered again.


func _hoverer(a_deceleration: float = -7.0) -> Movement:
	var body := Node3D.new()
	add_child_autofree(body)
	var aerial := Aerial.new()
	aerial.name = "Aerial"
	aerial.mode = Movement.Mode.HOVERING
	body.add_child(aerial)
	var movement := Movement.new()
	movement.name = "Locomotion"
	movement.speed = 9.0
	movement.max_deceleration = a_deceleration
	body.add_child(movement)
	return movement


func _aerial(a_movement: Movement) -> Aerial:
	return a_movement.get_parent().get_node("Aerial") as Aerial


func test_a_land_does_not_travel_on_and_a_move_does() -> void:
	var land := Land.new(CommandMessage.new(null, null, null, Vector3.ZERO))
	var move := MoveCommand.new(CommandMessage.new(null, null, null, Vector3.ZERO))
	assert_false(land.continues_movement(), "a move queued before it stops at its goal")
	assert_true(move.continues_movement(), "a move before a move keeps its speed")


func test_a_landing_is_predicted_where_the_unit_comes_to_rest() -> void:
	var aerial: Aerial = _aerial(_hoverer(-7.0))
	var offset: Vector2 = aerial._stopping_offset(Vector2(9.0, 0.0))
	assert_almost_eq(offset.x, 81.0 / 14.0, 0.001, "v² / 2a ahead, about 5.8")
	assert_almost_eq(offset.y, 0.0, 0.001)
	assert_eq(aerial._stopping_offset(Vector2.ZERO), Vector2.ZERO, "at rest, right here")


func test_unbounded_braking_stops_on_the_spot() -> void:
	var aerial: Aerial = _aerial(_hoverer(-INF))
	assert_eq(aerial._stopping_offset(Vector2(9.0, 0.0)), Vector2.ZERO)


func test_land_stays_on_offer_until_the_unit_is_coming_down() -> void:
	var movement: Movement = _hoverer()
	var aerial: Aerial = _aerial(movement)
	aerial._permanently_grounded = true
	assert_false(aerial.is_down_or_descending(), "ordered to land, but still airborne")
	aerial._landing_state = Aerial.LandingState.LANDING
	assert_true(aerial.is_down_or_descending(), "descending")
	aerial._landing_state = Aerial.LandingState.GROUNDED_TEMP
	assert_true(aerial.is_down_or_descending(), "down")
