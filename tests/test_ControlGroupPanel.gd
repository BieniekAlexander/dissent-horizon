extends GutTest

## The control-group PANEL: which buttons are on screen, and what each mouse button asks for.
##
## Both halves are static — visibility is a pure function of the ten head counts, and the
## gesture is a pure function of (mouse button, modifiers) — so neither needs a HUD, a
## controller in a tree, or a live selection. The keyboard's own table is
## `tests/test_ControlGroups.gd`; this file is only about what the buttons add to it.

const G := RTSController.ControlGroupGesture

## Ten head counts with `a_populated` (0-based group indices) holding one member each.
func _counts(a_populated: Array) -> Array:
	var counts: Array = []
	for i: int in RTSController.CONTROL_GROUP_COUNT:
		counts.append(1 if a_populated.has(i) else 0)
	return counts

#region Visibility — the populated run, plus the next empty slot
## Group 1 is shown EMPTY OR NOT, which is the authored base case the third rule chains from.
func test_the_first_button_is_always_shown() -> void:
	assert_true(ControlGroupPanel.button_is_visible(0, _counts([])),
		"an untouched game still shows the panel, or the feature is undiscoverable")
	assert_true(ControlGroupPanel.button_is_visible(0, _counts([0])),
		"and being populated does not change that")

func test_an_untouched_game_shows_only_the_first() -> void:
	var counts: Array = _counts([])
	for i: int in range(1, RTSController.CONTROL_GROUP_COUNT):
		assert_false(ControlGroupPanel.button_is_visible(i, counts),
			"group %d is hidden until something reaches it" % (i + 1))

func test_a_populated_group_is_shown() -> void:
	assert_true(ControlGroupPanel.button_is_visible(4, _counts([4])))

func test_the_group_after_a_populated_one_is_shown() -> void:
	assert_true(ControlGroupPanel.button_is_visible(5, _counts([4])),
		"there is always somewhere to assign to next")

func test_the_group_two_past_a_populated_one_is_hidden() -> void:
	assert_false(ControlGroupPanel.button_is_visible(6, _counts([4])))

func test_a_gap_does_not_chain_past_itself() -> void:
	# 1 populated, 2 empty, 3 populated: 4 is shown because 3 is populated, 5 is not.
	var counts: Array = _counts([0, 2])
	assert_true(ControlGroupPanel.button_is_visible(3, counts), "3 follows the populated 2")
	assert_false(ControlGroupPanel.button_is_visible(4, counts), "4 follows an empty one")

func test_an_index_outside_the_row_is_never_shown() -> void:
	assert_false(ControlGroupPanel.button_is_visible(-1, _counts([])))
	assert_false(ControlGroupPanel.button_is_visible(RTSController.CONTROL_GROUP_COUNT, _counts([])))
#endregion

#region The button's own modifier table
## LEFT reads the group and acts on the selection; RIGHT writes the group. That axis is what
## `modifier_broaden` spends on the number row, which is why the panel never reads it.
func test_left_click_recalls() -> void:
	assert_eq(RTSController.control_group_button_gesture(false, false, false), G.RECALL)

func test_right_click_assigns() -> void:
	assert_eq(RTSController.control_group_button_gesture(true, false, false), G.ASSIGN_GROUP)

func test_additive_left_adds_the_group_to_the_selection() -> void:
	assert_eq(RTSController.control_group_button_gesture(false, true, false), G.EXTEND_SELECTION)

func test_additive_right_adds_the_selection_to_the_group() -> void:
	assert_eq(RTSController.control_group_button_gesture(true, true, false), G.EXTEND_GROUP)

func test_narrow_left_takes_the_group_out_of_the_selection() -> void:
	assert_eq(RTSController.control_group_button_gesture(false, false, true), G.REMOVE_FROM_SELECTION)

func test_narrow_right_takes_the_selection_out_of_the_group() -> void:
	assert_eq(RTSController.control_group_button_gesture(true, false, true), G.REMOVE_FROM_GROUP)

## The two writes are opposites and cannot compose, so one has to win — the same precedence
## the keyboard table applies, for the same reason.
func test_narrow_beats_additive_on_both_buttons() -> void:
	assert_eq(RTSController.control_group_button_gesture(false, true, true), G.REMOVE_FROM_SELECTION)
	assert_eq(RTSController.control_group_button_gesture(true, true, true), G.REMOVE_FROM_GROUP)

## Every cell of the table is a DIFFERENT gesture — six presses, six outcomes. A collapsed
## cell would be a modifier the panel reads and then ignores.
func test_the_six_cells_are_six_distinct_gestures() -> void:
	var seen: Array = []
	for is_write: bool in [false, true]:
		for modifiers: Array in [[false, false], [true, false], [false, true]]:
			var gesture: int = RTSController.control_group_button_gesture(
				is_write, modifiers[0], modifiers[1])
			assert_false(seen.has(gesture), "gesture %d is reachable twice" % gesture)
			seen.append(gesture)
	assert_eq(seen.size(), 6)
#endregion

#region REMOVE_FROM_SELECTION — the gesture only the panel can reach
## The number row spends `broaden` on the read/write axis, so it has no cell left for this
## one; the panel's two mouse buttons carry that axis instead and free the modifier up.
func test_the_keyboard_table_cannot_reach_it() -> void:
	for additive: bool in [false, true]:
		for narrow: bool in [false, true]:
			for broaden: bool in [false, true]:
				assert_ne(
					RTSController.control_group_gesture(additive, narrow, broaden),
					G.REMOVE_FROM_SELECTION,
					"no keyboard modifier combination names it")

func test_it_edits_the_selection_and_leaves_the_group_alone() -> void:
	var controller := autofree(RTSController.new()) as RTSController
	var kept := add_child_autofree(Node.new()) as Node
	var dropped := add_child_autofree(Node.new()) as Node
	controller.selection = [kept, dropped]
	controller.apply_control_group_gesture(0, G.ASSIGN_GROUP)
	assert_eq(controller.control_group(0).size(), 2, "the group starts holding both")
	# Only `dropped` is in the group now, so removing the group from the selection must
	# leave `kept` behind.
	controller.selection = [kept, dropped]
	controller._control_groups[0] = [dropped]
	controller.apply_control_group_gesture(0, G.REMOVE_FROM_SELECTION)
	assert_eq(controller.control_group(0), [dropped], "the group is untouched")
#endregion
