extends GutTest

## The armed-order control scheme: which button carries out an armed order and which puts it down.
## Driven through RTSController._unhandled_input on a controller that was never in a scene tree,
## with synthetic action events, so no unarmed press is sent (that path reads the live pointer).
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_ControlScheme.gd -gexit

var _saved_scheme: ControlScheme.Kind
var _controller: RTSController


func before_each() -> void:
	_saved_scheme = ControlScheme.active
	_controller = autofree(RTSController.new()) as RTSController
	autofree(_controller.selection_box)
	_controller.command_message = CommandMessage.new(null)
	# Armed with a sanction-free, tool-free order: only the sub-mode name is set, which is armed
	# enough for the cancel half; the issue half is checked through the sources below.
	_controller.pending_command_name = "Build"


func after_each() -> void:
	ControlScheme.active = _saved_scheme


func _press(a_action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = a_action
	event.pressed = true
	_controller._unhandled_input(event)


func test_the_armed_actions_exist() -> void:
	assert_true(InputMap.has_action(ControlScheme.ARMED_ISSUE))
	assert_true(InputMap.has_action(ControlScheme.ARMED_CANCEL))


func test_the_swapped_scheme_sources_issue_from_the_left_click() -> void:
	assert_eq(ControlScheme.issue_source(ControlScheme.Kind.ARMED_SWAP), &"world_select")
	assert_eq(ControlScheme.cancel_source(ControlScheme.Kind.ARMED_SWAP), &"command_issue")


func test_the_classic_scheme_sources_issue_from_the_right_click() -> void:
	assert_eq(ControlScheme.issue_source(ControlScheme.Kind.CLASSIC), &"command_issue")
	assert_eq(ControlScheme.cancel_source(ControlScheme.Kind.CLASSIC), &"world_select")


func test_apply_copies_the_source_buttons_events_onto_the_armed_actions() -> void:
	for kind: ControlScheme.Kind in ControlScheme.Kind.values():
		ControlScheme.active = kind
		assert_eq(
			InputMap.action_get_events(ControlScheme.ARMED_ISSUE).size(),
			InputMap.action_get_events(ControlScheme.issue_source(kind)).size(),
			"issue events under %s" % kind
		)
		assert_eq(
			InputMap.action_get_events(ControlScheme.ARMED_CANCEL).size(),
			InputMap.action_get_events(ControlScheme.cancel_source(kind)).size(),
			"cancel events under %s" % kind
		)


func test_a_real_click_matches_its_armed_action_under_each_scheme() -> void:
	var left := InputEventMouseButton.new()
	left.button_index = MOUSE_BUTTON_LEFT
	left.pressed = true
	ControlScheme.active = ControlScheme.Kind.ARMED_SWAP
	assert_true(ControlScheme.matches(left, ControlScheme.ARMED_ISSUE))
	assert_false(ControlScheme.matches(left, ControlScheme.ARMED_CANCEL))
	ControlScheme.active = ControlScheme.Kind.CLASSIC
	assert_true(ControlScheme.matches(left, ControlScheme.ARMED_CANCEL))
	assert_false(ControlScheme.matches(left, ControlScheme.ARMED_ISSUE))


func test_swapped_the_right_click_puts_the_armed_order_down() -> void:
	ControlScheme.active = ControlScheme.Kind.ARMED_SWAP
	_press(&"command_issue")
	assert_eq(_controller.pending_command_name, "")


func test_swapped_the_left_click_does_not_put_it_down() -> void:
	ControlScheme.active = ControlScheme.Kind.ARMED_SWAP
	# The left click issues here; with no selection it orders nothing but must not cancel.
	_press(&"world_select")
	assert_eq(_controller.pending_command_name, "Build")


func test_classic_the_left_click_puts_the_armed_order_down() -> void:
	ControlScheme.active = ControlScheme.Kind.CLASSIC
	_press(&"world_select")
	assert_eq(_controller.pending_command_name, "")


func test_classic_the_right_click_does_not_put_it_down() -> void:
	ControlScheme.active = ControlScheme.Kind.CLASSIC
	_press(&"command_issue")
	assert_eq(_controller.pending_command_name, "Build")


func test_the_armed_cancel_action_itself_puts_it_down_under_either_scheme() -> void:
	for kind: ControlScheme.Kind in ControlScheme.Kind.values():
		ControlScheme.active = kind
		_controller.pending_command_name = "Build"
		_press(ControlScheme.ARMED_CANCEL)
		assert_eq(_controller.pending_command_name, "", "cancelled under %s" % kind)
