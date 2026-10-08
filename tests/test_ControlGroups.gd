extends GutTest

## Control groups: the modifier table, the action naming, and the set arithmetic the five
## gestures are built out of.
##
## Everything here is either static or touches nothing but `selection` and the ten group
## arrays, so it runs on a bare RTSController that was never put in a scene tree. The two
## gestures that CHANGE the selection (recall / extend) go through _select_units, which
## refreshes the HUD, and are exercised in play rather than here.

const A := RTSController.ControlGroupGesture


func _controller() -> RTSController:
	# Never added to the tree: _ready would want a Map, a camera and the whole HUD rig, and
	# none of the group rules read any of it.
	return autofree(RTSController.new()) as RTSController


## A stand-in for a selected unit. The group rules are set arithmetic over whatever the
## selection held, and they ask a Node two questions — is it still valid, is it still in the
## world — so a bare Node answers both without dragging a whole entity scene in.
func _unit(a_name: String) -> Node:
	var n := Node.new()
	n.name = a_name
	return add_child_autofree(n)


#region The modifier table
## |                  | none          | additive              |
## | *none*           | recall        | add group to selection|
## | modifier_narrow  | take out      | (unused)              |
## | modifier_broaden | set the group | add to the group      |
func test_a_bare_press_recalls_the_group() -> void:
	assert_eq(RTSController.control_group_gesture(false, false, false), A.RECALL)


func test_additive_adds_the_group_to_the_selection() -> void:
	assert_eq(RTSController.control_group_gesture(true, false, false), A.EXTEND_SELECTION)


func test_narrow_takes_the_selection_out_of_the_group() -> void:
	assert_eq(RTSController.control_group_gesture(false, true, false), A.REMOVE_FROM_GROUP)


func test_broaden_sets_the_group_to_the_selection() -> void:
	assert_eq(RTSController.control_group_gesture(false, false, true), A.ASSIGN_GROUP)


func test_broaden_with_additive_adds_to_the_group() -> void:
	assert_eq(RTSController.control_group_gesture(true, false, true), A.EXTEND_GROUP)


## The table leaves narrow+additive unused, and both write modifiers together names two
## opposite writes. Narrow wins in each case — the row order, and nothing deeper — so the
## press always does something rather than being refused.
func test_narrow_wins_over_the_other_modifiers() -> void:
	assert_eq(RTSController.control_group_gesture(true, true, false), A.REMOVE_FROM_GROUP)
	assert_eq(RTSController.control_group_gesture(false, true, true), A.REMOVE_FROM_GROUP)
	assert_eq(RTSController.control_group_gesture(true, true, true), A.REMOVE_FROM_GROUP)


#endregion


#region Actions
## The key is a default; the ACTION is the binding. A rebinding screen rewrites
## project.godot, and nothing in the code names a digit.
func test_every_group_has_an_input_action_with_a_key() -> void:
	assert_eq(RTSController.control_group_actions().size(), RTSController.CONTROL_GROUP_COUNT)
	for action: StringName in RTSController.control_group_actions():
		assert_true(InputMap.has_action(action), "project.godot defines '%s'" % action)
		assert_false(InputMap.action_get_events(action).is_empty(), "'%s' has a key bound" % action)


## Defaults follow the number row, with 0 standing for the tenth group.
func test_the_default_keys_are_the_number_row() -> void:
	var expected: Array = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
	for i: int in RTSController.CONTROL_GROUP_COUNT:
		assert_eq(
			InputPrompt.action_text(RTSController.control_group_action(i)),
			expected[i],
			"group %d" % (i + 1)
		)


func test_an_action_round_trips_through_its_index() -> void:
	for i: int in RTSController.CONTROL_GROUP_COUNT:
		assert_eq(
			RTSController.control_group_index_from_action(
				String(RTSController.control_group_action(i))
			),
			i
		)


## A control-group action is NOT a `command_` action — the hotkey dispatcher routes every
## one of those into the command grid, and a group changes the selection rather than
## acting on it.
func test_control_group_actions_are_not_command_actions() -> void:
	for action: StringName in RTSController.control_group_actions():
		assert_false(String(action).begins_with("command_"), String(action))


func test_unrelated_actions_have_no_group_index() -> void:
	for name: String in [
		"command_cell_0_0",
		"modifier_additive",
		"",
		"control_group_",
		"control_group_0",
		"control_group_11",
		"control_group_x"
	]:
		assert_eq(RTSController.control_group_index_from_action(name), -1, name)


#endregion


#region Set arithmetic
func test_with_members_appends_without_duplicating() -> void:
	var a: Node = _unit("a")
	var b: Node = _unit("b")
	assert_eq(RTSController.with_members([a], [b, a]), [a, b])


func test_without_members_removes_by_identity() -> void:
	var a: Node = _unit("a")
	var b: Node = _unit("b")
	assert_eq(RTSController.without_members([a, b], [a]), [b])
	assert_eq(RTSController.without_members([a, b], []), [a, b])


func test_live_members_drops_anything_out_of_the_world() -> void:
	var a: Node = _unit("a")
	var orphan := autofree(Node.new()) as Node
	assert_eq(RTSController.live_members([a, orphan, null]), [a])


## Regression: a member killed since it was grouped is a FREED object, and casting one is an
## error — the panel reads the groups every frame, so it fired as soon as a grouped unit died.
func test_live_members_drops_a_freed_member_without_casting_it() -> void:
	var a: Node = _unit("a")
	var dead := Node.new()
	add_child(dead)
	dead.free()
	assert_eq(RTSController.live_members([dead, a]), [a])


#endregion


#region Gestures that edit a group
func test_assign_makes_the_group_the_selection() -> void:
	var controller: RTSController = _controller()
	var a: Node = _unit("a")
	controller.selection = [a]
	controller.apply_control_group_gesture(0, A.ASSIGN_GROUP)
	assert_eq(controller.control_group(0), [a])


func test_assign_replaces_what_the_group_held() -> void:
	var controller: RTSController = _controller()
	var a: Node = _unit("a")
	var b: Node = _unit("b")
	controller.selection = [a]
	controller.apply_control_group_gesture(0, A.ASSIGN_GROUP)
	controller.selection = [b]
	controller.apply_control_group_gesture(0, A.ASSIGN_GROUP)
	assert_eq(controller.control_group(0), [b])


func test_extend_keeps_what_the_group_held() -> void:
	var controller: RTSController = _controller()
	var a: Node = _unit("a")
	var b: Node = _unit("b")
	controller.selection = [a]
	controller.apply_control_group_gesture(0, A.ASSIGN_GROUP)
	controller.selection = [b, a]
	controller.apply_control_group_gesture(0, A.EXTEND_GROUP)
	assert_eq(controller.control_group(0), [a, b], "no duplicate for the member already in")


func test_remove_takes_the_selection_out_and_leaves_the_rest() -> void:
	var controller: RTSController = _controller()
	var a: Node = _unit("a")
	var b: Node = _unit("b")
	controller.selection = [a, b]
	controller.apply_control_group_gesture(0, A.ASSIGN_GROUP)
	controller.selection = [a]
	controller.apply_control_group_gesture(0, A.REMOVE_FROM_GROUP)
	assert_eq(controller.control_group(0), [b])


func test_the_groups_are_independent() -> void:
	var controller: RTSController = _controller()
	var a: Node = _unit("a")
	controller.selection = [a]
	controller.apply_control_group_gesture(3, A.ASSIGN_GROUP)
	assert_eq(controller.control_group(3), [a])
	assert_eq(controller.control_group(4), [])


func test_an_index_outside_the_ten_is_ignored() -> void:
	var controller: RTSController = _controller()
	controller.selection = [_unit("a")]
	controller.apply_control_group_gesture(-1, A.ASSIGN_GROUP)
	controller.apply_control_group_gesture(RTSController.CONTROL_GROUP_COUNT, A.ASSIGN_GROUP)
	assert_eq(controller.control_group(-1), [])
	assert_eq(controller.control_group(RTSController.CONTROL_GROUP_COUNT), [])


#endregion

#region The double tap
## One press selects a group; only a second press of the SAME group, quickly, moves the camera.
const TAP_WINDOW_MS: int = int(RTSController.DOUBLE_CLICK_SECONDS * 1000.0)


func test_a_second_press_of_the_same_group_in_the_window_is_a_double_tap() -> void:
	assert_true(RTSController.is_double_tap(2, 1000, 2, 1000 + TAP_WINDOW_MS))


func test_a_slow_second_press_is_not() -> void:
	assert_false(RTSController.is_double_tap(2, 1000, 2, 1001 + TAP_WINDOW_MS))


func test_a_press_of_another_group_is_not() -> void:
	assert_false(RTSController.is_double_tap(2, 1000, 3, 1001))


func test_the_first_press_is_not() -> void:
	assert_false(RTSController.is_double_tap(-1, 0, 0, 0))


func test_a_write_between_two_reads_breaks_the_pair() -> void:
	# An empty group and an empty selection: this pins the tap memory, not what gets selected.
	var controller: RTSController = _controller()
	controller.apply_control_group_gesture(0, A.RECALL)
	assert_eq(controller._last_group_tap_index, 0, "a read is remembered")
	controller.apply_control_group_gesture(0, A.ASSIGN_GROUP)
	assert_eq(controller._last_group_tap_index, -1, "a write is not a tap")
#endregion
