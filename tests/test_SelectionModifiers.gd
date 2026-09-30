extends GutTest

## The two selection modifiers the world and the minimap gained: `modifier_narrow` as a SET
## DIFFERENCE, and the pan-sensitivity pair on a camera drag.
##
## The narrow gesture is tested through its world-space entry point
## (`select_units_in_world_rect`, what the minimap drags) rather than through the viewport
## one, because the viewport path needs a camera to unproject against and the RULE is the
## same either way — take out what the gesture caught, keep everything else.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd \
##     -gtest=res://tests/test_SelectionModifiers.gd -gexit

func _controller() -> RTSController:
	return autofree(RTSController.new()) as RTSController


## A real unit standing at `a_xz`, owned by `a_commander`. A bare `Commandable.new()` will not
## do — the class has required `@onready` children (an HP bar, a Selectable) and errors
## without them — and the gesture genuinely needs both a world position and a live Selectable.
##
## Ownership is assigned
## directly rather than through initialize(), so no Map is needed (see test_Garrison).
func _unit_at(a_xz: Vector2, a_commander: Commander) -> Commandable:
	var unit: Commandable = FakePieces.unit(FakePieces.PLAIN)
	add_child_autofree(unit)
	unit.ownership.commander = a_commander
	unit.global_position = VU.fromXZ(a_xz)
	return unit


func _player() -> Commander:
	var commander := Commander.new()
	commander.id = RTSController.PLAYER_COMMANDER_ID
	add_child_autofree(commander)
	return commander


#region modifier_narrow — set difference
## Ten selected, a box over three: seven remain. The case Alex spelled out.
func test_a_narrow_rect_removes_only_what_it_covers() -> void:
	var controller: RTSController = _controller()
	var commander: Commander = _player()
	var inside: Array[Node] = []
	var outside: Array[Node] = []
	for i: int in 3:
		inside.append(_unit_at(Vector2(i, 0), commander))
	for i: int in 7:
		outside.append(_unit_at(Vector2(100 + i, 0), commander))
	controller.selection = []
	controller.selection.assign(inside + outside)

	controller._deselect_in_world_rect(Rect2(Vector2(-1, -1), Vector2(10, 2)))

	assert_eq(controller.selection.size(), 7, "the three inside the box came out")
	for node: Node in inside:
		assert_false(controller.selection.has(node), "a covered unit is deselected")
	for node: Node in outside:
		assert_true(controller.selection.has(node), "an uncovered one is untouched")


## It is a DIFFERENCE, not an intersection: a unit inside the rectangle that was never
## selected is not selected by the gesture.
func test_it_never_selects_anything() -> void:
	var controller: RTSController = _controller()
	var commander: Commander = _player()
	var selected: Commandable = _unit_at(Vector2(50, 0), commander)
	var bystander: Commandable = _unit_at(Vector2(0, 0), commander)
	controller.selection = [selected] as Array[Node]

	controller._deselect_in_world_rect(Rect2(Vector2(-1, -1), Vector2(10, 2)))

	assert_false(controller.selection.has(bystander),
		"a unit under the box that was not selected stays unselected")
	assert_true(controller.selection.has(selected),
		"and one outside it that WAS selected stays selected")


func test_a_rect_over_nothing_selected_changes_nothing() -> void:
	var controller: RTSController = _controller()
	var commander: Commander = _player()
	var kept: Commandable = _unit_at(Vector2(50, 0), commander)
	controller.selection = [kept] as Array[Node]
	controller._deselect_in_world_rect(Rect2(Vector2(-100, -100), Vector2(1, 1)))
	assert_eq(controller.selection, [kept] as Array[Node])
#endregion


#region Pan sensitivity
## Unmodified drags are unchanged — the factor is a multiplier on 1.0, so a camera with no
## modifier held pans exactly as it did before either factor existed.
func test_an_unmodified_drag_is_unscaled() -> void:
	var camera := autofree(RTSCamera3D.new()) as RTSCamera3D
	assert_almost_eq(camera.drag_pan_factor(), 1.0, 0.0001)


## The two are opposite scalars, so holding both cancels to 1.0 — which is why this needs no
## precedence rule where the control-group table needs one.
func test_the_two_factors_cancel() -> void:
	var camera := autofree(RTSCamera3D.new()) as RTSCamera3D
	assert_almost_eq(camera.precise_pan_factor * camera.fast_pan_factor, 1.0, 0.0001,
		"held together they must come back to unmodified, or the pair needs a winner")


## Narrow restricts and broaden widens, the direction those two carry in every key space.
func test_narrow_slows_and_broaden_speeds() -> void:
	var camera := autofree(RTSCamera3D.new()) as RTSCamera3D
	assert_lt(camera.precise_pan_factor, 1.0, "narrow is fine control")
	assert_gt(camera.fast_pan_factor, 1.0, "broaden is a fast sweep")
#endregion


#region Bulk purchase
## `modifier_broaden` on a train button buys a batch; unmodified it buys one.
func test_one_press_buys_one_without_the_modifier() -> void:
	var controller: RTSController = _controller()
	assert_eq(controller.bulk_purchase_count(), 1,
		"no modifier is held in a headless test, which is the unmodified case")


func test_the_batch_size_is_a_named_constant() -> void:
	assert_gt(RTSController.BULK_PURCHASE_COUNT, 1,
		"a batch of one would make the modifier a no-op")
#endregion
