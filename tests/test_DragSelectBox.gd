extends GutTest

## The box-select drag: the rectangle the player drags, and the click-vs-drag threshold
## that decides whether a release resolves as a point click or as a box.
##
## Bare RTSController instances (never added to the tree) — the drag geometry needs
## nothing but the controller's own `selection_box`, which the export default supplies.
## The parts that DO need a scenario (resolving the selection, the over-HUD test) are
## driven by the real game; what is pinned here is the geometry and the threshold.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_DragSelectBox.gd -gexit


func _controller() -> RTSController:
	var controller := RTSController.new()
	autofree(controller)
	autofree(controller.selection_box)
	# What _ready does with the box, which a bare instance never runs: it starts hidden and
	# is only raised by a press.
	controller.selection_box.visible = false
	return controller


# --- The box follows the cursor ---------------------------------------------------


func test_a_fresh_drag_starts_as_an_empty_box_at_the_press() -> void:
	var controller := _controller()
	controller.begin_drag_at(Vector2(100, 100))

	assert_true(controller.selection_box.visible, "the box is up")
	assert_eq(controller.selection_box.position, Vector2(100, 100))
	assert_eq(controller.selection_box.size, Vector2.ZERO)


func test_the_box_grows_with_the_cursor() -> void:
	var controller := _controller()
	controller.begin_drag_at(Vector2(100, 100))
	controller.update_drag_to(Vector2(180, 260))

	assert_eq(controller.selection_box.position, Vector2(100, 100))
	assert_eq(controller.selection_box.size, Vector2(80, 160))


func test_the_box_is_normalized_when_dragged_up_and_left() -> void:
	# Dragging back past the press point must still produce a positive-size rect anchored
	# at the top-left corner, not a negative one.
	var controller := _controller()
	controller.begin_drag_at(Vector2(300, 300))
	controller.update_drag_to(Vector2(220, 140))

	assert_eq(controller.selection_box.position, Vector2(220, 140))
	assert_eq(controller.selection_box.size, Vector2(80, 160))


func test_the_box_keeps_growing_below_the_hud_edge() -> void:
	# The regression: a drag that crossed onto the HUD used to freeze, because the panels
	# swallow the MouseMotion the box was driven from. The box is now driven from the live
	# cursor per frame, so a position over the panels is just another position.
	var controller := _controller()
	controller.begin_drag_at(Vector2(200, 200))
	controller.update_drag_to(Vector2(400, 700))
	var over_hud: Vector2 = Vector2(400, 900)
	controller.update_drag_to(over_hud)

	assert_eq(controller.selection_box.size, Vector2(200, 700), "still tracking past the HUD edge")


func test_a_release_with_no_drag_in_progress_resolves_nothing() -> void:
	# The guard that lets a press over a HUD panel be ignored outright: it starts no drag,
	# so the matching release must fall straight through rather than resolving a selection
	# against a stale anchor. (Reaching the resolution at all would need a live scenario —
	# this returning quietly is the whole assertion.)
	var controller := _controller()
	controller.end_drag_at(Vector2(90, 90))

	assert_false(controller.selection_box.visible, "no box was ever raised")


# --- Click or drag ----------------------------------------------------------------


func test_a_press_and_release_in_the_same_place_is_a_click() -> void:
	assert_true(RTSController.is_click_gesture(Vector2(50, 50), Vector2(50, 50)))
	assert_true(
		RTSController.is_click_gesture(Vector2(50, 50), Vector2(56, 44)),
		"a few pixels of hand tremor is still a click"
	)


func test_a_box_in_either_axis_is_a_drag() -> void:
	assert_false(
		RTSController.is_click_gesture(Vector2(50, 50), Vector2(400, 50)), "a wide, flat drag"
	)
	# The bug this pins: the old test compared the delta against Vector2(10, 10), and
	# Vector2's `<` is LEXICOGRAPHIC — x decides unless the xs are equal — so a tall,
	# narrow drag read as a click and selected the single unit under the press instead.
	assert_false(
		RTSController.is_click_gesture(Vector2(50, 50), Vector2(55, 550)), "a tall, narrow drag"
	)


# --- The minimap's drag reads the modifier the same way ----------------------------


## A minimap box-select is a Control's _gui_input, so the modifier keypress before it went
## to the focused Control and never reached the controller's _unhandled_input — the latch
## can't be trusted there. `minimap.gd` therefore polls through this accessor, and it named
## a property that does not exist: every box-select onto the minimap died with "Invalid
## access to property or key 'next_modifier_additive'".
func test_the_controller_exposes_the_polled_additive_read() -> void:
	var controller := _controller()
	assert_true(controller.has_method("additive_modifier_held"), "the name minimap.gd calls")
	assert_false(
		controller.additive_modifier_held(),
		"nothing is held in a headless run, and asking must not error"
	)
