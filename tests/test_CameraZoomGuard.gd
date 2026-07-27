extends GutTest

## Tests for RTSCamera3D.zoom_allowed — whether a zoom binding applies given where the
## cursor is.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_CameraZoomGuard.gd -gexit
##
## The rule exists because "isometric_camera_zoom_in/out" is bound to BOTH the mouse wheel
## and a key: a wheel notch is aimed at whatever is under the cursor, a keypress is not.
## These drive the pure decision directly; the live lookup behind it (_pointer_over_ui,
## which needs a viewport and a HUD) is exercised by hand.


func _wheel(a_button: int) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = a_button
	event.pressed = true
	return event


func _key(a_keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = a_keycode
	event.pressed = true
	return event


# --- Wheel: aimed at what's under the cursor ------------------------------------

func test_wheel_zooms_over_the_world():
	assert_true(RTSCamera3D.zoom_allowed(_wheel(MOUSE_BUTTON_WHEEL_UP), false))
	assert_true(RTSCamera3D.zoom_allowed(_wheel(MOUSE_BUTTON_WHEEL_DOWN), false))


func test_wheel_does_nothing_over_ui():
	# The motivating case: scrolling over the minimap, a command panel or an open dialog
	# must not zoom the world behind it.
	assert_false(RTSCamera3D.zoom_allowed(_wheel(MOUSE_BUTTON_WHEEL_UP), true))
	assert_false(RTSCamera3D.zoom_allowed(_wheel(MOUSE_BUTTON_WHEEL_DOWN), true))


# --- Keyboard: aimed at nothing -------------------------------------------------

func test_key_zooms_even_when_the_cursor_rests_on_ui():
	# The HUD lines the bottom of the screen, so the cursor sits on it constantly — after
	# every button click. Suppressing the key binding by cursor position would make +/- feel
	# randomly broken.
	assert_true(RTSCamera3D.zoom_allowed(_key(KEY_EQUAL), true))
	assert_true(RTSCamera3D.zoom_allowed(_key(KEY_MINUS), true))


func test_key_zooms_over_the_world():
	assert_true(RTSCamera3D.zoom_allowed(_key(KEY_EQUAL), false))


# --- The dialog window counts as blocking UI ------------------------------------

func test_dialog_panel_joins_the_blocking_ui_group():
	# A dialog is built in code rather than authored in player.tscn, so it can only reach
	# the group by adding itself — and the zoom guard is only as good as that membership.
	var view := ScenarioDialogView.new()
	add_child_autofree(view)

	var blocking: Array = get_tree().get_nodes_in_group(RTSController.SELECTION_BLOCKING_UI_GROUP)
	var panel: Node = view.get_node_or_null("DialogRoot/Center/Panel")
	assert_not_null(panel, "the dialog panel was built")
	assert_true(blocking.has(panel), "the dialog panel blocks pointer input while visible")


func test_a_closed_dialog_blocks_nothing():
	# Group membership is permanent; pointer_over_blocking_ui gates on is_visible_in_tree,
	# so the closed window must not be visible or it would block the whole screen forever.
	var view := ScenarioDialogView.new()
	add_child_autofree(view)

	var panel: Control = view.get_node_or_null("DialogRoot/Center/Panel") as Control
	assert_not_null(panel)
	assert_false(panel.is_visible_in_tree(), "no dialog is up, so nothing is blocked")
