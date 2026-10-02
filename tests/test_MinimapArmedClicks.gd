extends GutTest

## The minimap follows the armed-order control scheme (ControlScheme): while an order is armed, its
## armed-issue button orders at the clicked point and its armed-cancel button puts the order down.
## The handler is driven directly with synthetic clicks; the pixel-to-world maths is injected.
##
## Run with:
## godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_MinimapArmedClicks.gd -gexit


class RecordingController:
	extends RTSController
	var issued_at: Array[Vector2] = []

	func issue_command_at_world_position(a_world_xz: Vector2) -> void:
		issued_at.append(a_world_xz)


var _saved_scheme: ControlScheme.Kind
var _minimap: Minimap
var _controller: RecordingController


func before_each() -> void:
	_saved_scheme = ControlScheme.active
	_minimap = Minimap.new()
	add_child_autofree(_minimap)
	_minimap._ready_to_draw = true
	_minimap._world_half_w = 48.0
	_minimap._world_half_d = 27.0
	_minimap._world_center = Vector2.ZERO
	_minimap._screen_aligned = false
	_minimap._world_units_per_pixel = 96.0 / float(Minimap.WIDTH)
	_controller = autofree(RecordingController.new()) as RecordingController
	autofree(_controller.selection_box)
	_controller.command_message = CommandMessage.new(null)
	_minimap._controller = _controller


func after_each() -> void:
	ControlScheme.active = _saved_scheme


func _click(a_button: MouseButton) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = a_button
	event.pressed = true
	event.position = Vector2(10.0, 10.0)
	return event


func test_unarmed_clicks_are_left_for_the_minimaps_own_reading() -> void:
	for kind: ControlScheme.Kind in ControlScheme.Kind.values():
		ControlScheme.active = kind
		assert_false(_minimap._handle_armed_press(_click(MOUSE_BUTTON_LEFT)))
		assert_false(_minimap._handle_armed_press(_click(MOUSE_BUTTON_RIGHT)))
	assert_eq(_controller.issued_at.size(), 0)


func test_swapped_left_click_orders_and_right_click_cancels() -> void:
	ControlScheme.active = ControlScheme.Kind.ARMED_SWAP
	_controller.pending_command_name = "Build"
	assert_true(_minimap._handle_armed_press(_click(MOUSE_BUTTON_LEFT)))
	assert_eq(_controller.issued_at.size(), 1, "ordered at the clicked point")
	assert_eq(_controller.pending_command_name, "Build", "and did not cancel")
	assert_true(_minimap._handle_armed_press(_click(MOUSE_BUTTON_RIGHT)))
	assert_eq(_controller.pending_command_name, "")
	assert_eq(_controller.issued_at.size(), 1)


func test_classic_right_click_orders_and_left_click_cancels() -> void:
	ControlScheme.active = ControlScheme.Kind.CLASSIC
	_controller.pending_command_name = "Build"
	assert_true(_minimap._handle_armed_press(_click(MOUSE_BUTTON_RIGHT)))
	assert_eq(_controller.issued_at.size(), 1)
	assert_true(_minimap._handle_armed_press(_click(MOUSE_BUTTON_LEFT)))
	assert_eq(_controller.pending_command_name, "")


func test_a_release_is_not_taken() -> void:
	_controller.pending_command_name = "Build"
	var release: InputEventMouseButton = _click(MOUSE_BUTTON_LEFT)
	release.pressed = false
	assert_false(_minimap._handle_armed_press(release))
