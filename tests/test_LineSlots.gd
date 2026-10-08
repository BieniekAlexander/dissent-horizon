extends GutTest

## The geometry of a move-line order (LineSlots) and the rules the controller builds on it: which
## orders may be drawn as a line, and how a mixed selection is laid out along one.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_LineSlots.gd -gexit

const SPACING: float = 2.0
const BACK: Vector2 = Vector2(0, 1)


func _controller() -> RTSController:
	var controller := RTSController.new()
	autofree(controller)
	autofree(controller.selection_box)
	return controller


func _unit(a_options: Dictionary, a_xz: Vector2) -> Actor:
	var unit: Actor = FakePieces.unit(a_options)
	add_child_autofree(unit)
	unit.global_position = Vector3(a_xz.x, 0.0, a_xz.y)
	return unit


#region Slots
func test_one_actor_takes_the_end_of_the_line() -> void:
	var slots: Array[Vector2] = LineSlots.slots(Vector2.ZERO, Vector2(10, 0), SPACING, 1, BACK)
	assert_eq(slots, [Vector2(10, 0)] as Array[Vector2])


func test_a_long_line_spaces_everyone_equally_end_to_end() -> void:
	var slots: Array[Vector2] = LineSlots.slots(Vector2.ZERO, Vector2(20, 0), SPACING, 5, BACK)
	assert_eq(slots.size(), 5)
	assert_eq(slots[0], Vector2(0, 0))
	assert_eq(slots[4], Vector2(20, 0))
	assert_almost_eq(slots[2].x, 10.0, 0.001)
	for slot: Vector2 in slots:
		assert_almost_eq(slot.y, 0.0, 0.001, "single file stays on the line")


func test_a_short_line_forms_rows_on_the_back_side() -> void:
	# Length 4 at spacing 2 holds 3 per row; 7 actors make rows of 3, 3 and 1.
	var slots: Array[Vector2] = LineSlots.slots(Vector2.ZERO, Vector2(4, 0), SPACING, 7, BACK)
	assert_eq(slots.size(), 7)
	assert_almost_eq(slots[0].y, 0.0, 0.001, "first row on the line")
	assert_almost_eq(slots[3].y, SPACING, 0.001, "second row one spacing back")
	assert_almost_eq(slots[6].y, SPACING * 2.0, 0.001)
	assert_almost_eq(slots[6].x, 2.0, 0.001, "a lone last actor is centred, not bunched at an end")


func test_a_line_with_no_length_stacks_in_a_column() -> void:
	var slots: Array[Vector2] = LineSlots.slots(Vector2(3, 3), Vector2(3, 3), SPACING, 3, BACK)
	assert_eq(slots.size(), 3)
	assert_almost_eq(slots[1].y - slots[0].y, SPACING, 0.001)


func test_no_two_slots_are_closer_than_the_spacing() -> void:
	for count: int in [2, 5, 9, 16]:
		var slots: Array[Vector2] = LineSlots.slots(Vector2.ZERO, Vector2(6, 0), SPACING, count, BACK)
		for i: int in slots.size():
			for j: int in range(i + 1, slots.size()):
				assert_gte(slots[i].distance_to(slots[j]), SPACING - 0.001, "%d actors" % count)


func test_back_points_toward_the_actors() -> void:
	var back: Vector2 = LineSlots.back_toward(Vector2.ZERO, Vector2(10, 0), Vector2(5, -20))
	assert_almost_eq(back.y, -1.0, 0.001)
#endregion


#region Assignment
func test_every_actor_gets_a_distinct_slot() -> void:
	var actors: Array[Vector2] = [Vector2(5, 9), Vector2(1, 8), Vector2(9, 9), Vector2(3, 9)]
	var slots: Array[Vector2] = LineSlots.slots(Vector2.ZERO, Vector2(12, 0), SPACING, 4, BACK)
	var taken: Array[int] = LineSlots.assign(actors, slots, Vector2.RIGHT)
	var seen: Dictionary = {}
	for index: int in taken:
		assert_true(index >= 0 and index < 4)
		seen[index] = true
	assert_eq(seen.size(), 4)


func test_the_left_most_actor_takes_the_left_most_slot() -> void:
	var actors: Array[Vector2] = [Vector2(8, 9), Vector2(1, 9), Vector2(4, 9)]
	var slots: Array[Vector2] = LineSlots.slots(Vector2.ZERO, Vector2(12, 0), SPACING, 3, BACK)
	var taken: Array[int] = LineSlots.assign(actors, slots, Vector2.RIGHT)
	assert_eq(taken[1], 0)
	assert_eq(taken[2], 1)
	assert_eq(taken[0], 2)


func test_assignment_is_the_same_every_time() -> void:
	var actors: Array[Vector2] = [Vector2(2, 2), Vector2(2, 2), Vector2(2, 2)]
	var slots: Array[Vector2] = LineSlots.slots(Vector2.ZERO, Vector2(8, 0), SPACING, 3, BACK)
	assert_eq(LineSlots.assign(actors, slots, Vector2.RIGHT), LineSlots.assign(actors, slots, Vector2.RIGHT))
#endregion


#region Which orders may be a line
func test_plain_and_purposeful_moves_may_be_lines() -> void:
	for command: Script in [MoveCommand, AttackMove, Patrol, Defend]:
		assert_true(RTSController.line_capable(command), str(command))


func test_orders_that_are_not_a_move_may_not() -> void:
	for command: Script in [Build, FocusFire, Train, Attack, Embark, Stop, null]:
		assert_false(RTSController.line_capable(command), str(command))
#endregion


#region Laying out a selection
func test_an_immobile_actor_takes_no_slot() -> void:
	var mover: Actor = _unit({"speed": 2.0}, Vector2(0, 5))
	var still: Actor = _unit({}, Vector2(1, 5))
	assert_eq(OrderDispatcher.line_movers([mover, still]), [mover])


func test_a_lone_actor_goes_to_the_end_of_the_line() -> void:
	var controller := _controller()
	controller._line_start = Vector2(0, 0)
	controller._line_end = Vector2(10, 0)
	var mover: Actor = _unit({"speed": 2.0}, Vector2(0, 5))
	var result: Dictionary = controller._line_destinations([mover])
	assert_eq(result[mover], Vector2(10, 0))


func test_ground_and_air_each_fill_the_whole_line() -> void:
	var controller := _controller()
	controller._line_start = Vector2(0, 0)
	controller._line_end = Vector2(20, 0)
	var ground: Array[Actor] = [
		_unit({"speed": 2.0}, Vector2(0, 5)), _unit({"speed": 2.0}, Vector2(4, 5))
	]
	var air: Array[Actor] = [
		_unit({"aerial": true}, Vector2(0, 8)), _unit({"aerial": true}, Vector2(4, 8))
	]
	var result: Dictionary = controller._line_destinations(ground + air)
	assert_eq(result.size(), 4)
	var ground_xs: Array = [result[ground[0]].x, result[ground[1]].x]
	var air_xs: Array = [result[air[0]].x, result[air[1]].x]
	ground_xs.sort()
	air_xs.sort()
	assert_eq(ground_xs, [0.0, 20.0], "two ground units span the line, ends included")
	assert_eq(air_xs, [0.0, 20.0], "so do two aircraft, laid out on their own")
#endregion
