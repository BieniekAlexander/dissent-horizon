extends GutTest

## The selector key scheme: three families on F1 / F2 / F3, broadened by two polled
## modifiers, with the alphabetical block left entirely to unit commands.
##
## This is the observable half of retiring idiom V ("one key can mean two things; the unit
## command wins"). The precedence rule it names was invisible to the player and is gone —
## what replaces it is that the collision cannot occur, and that is a property of the
## BINDINGS, which is what this file pins. The behaviour behind each key (which cell of the
## matrix a modifier combination yields) needs a live scenario, a camera and a selection to
## exercise, and is not covered here.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_SelectorBindings.gd -gexit

const _SELECTOR_ACTIONS: Array[String] = [
	RTSController.CMD_SELECT_ARMY,
	RTSController.CMD_SELECT_BUILDER,
	RTSController.CMD_SELECT_PRODUCTION,
]

## The nine letter-bound selectors idiom V's precedence rule existed to arbitrate.
const _RETIRED_ACTIONS: Array[String] = [
	"command_select_idle_combat",
	"command_select_army_on_screen",
	"command_select_army_all",
	"command_select_idle_builder",
	"command_select_builders_on_screen",
	"command_select_builders_all",
	"command_select_idle_production",
	"command_select_production_on_screen",
	"command_select_production_all",
]


## Every key the command grid is bound to. A selector sharing one of these would resurrect
## the collision.
##
## Asked of the CELLS rather than of a list of verbs, because a grid command has no key of
## its own any more — the cell carries the key and the command is whatever that cell draws
## (see ControlBinding.CELL_ACTION_PREFIX). A hand-written verb list would now name actions
## that no longer exist, and this check would pass by finding no keys to compare against.
static func _grid_actions() -> Array:
	return ControlBinding.cell_actions()


func _physical_keycodes(a_action: String) -> Array[int]:
	var out: Array[int] = []
	for event: InputEvent in InputMap.action_get_events(a_action):
		var key := event as InputEventKey
		if key != null:
			out.append(key.physical_keycode)
	return out


# --- The three selector keys --------------------------------------------------


func test_the_three_selectors_are_bound_to_f1_f2_f3() -> void:
	assert_eq(_physical_keycodes(RTSController.CMD_SELECT_ARMY), [KEY_F1] as Array[int])
	assert_eq(_physical_keycodes(RTSController.CMD_SELECT_BUILDER), [KEY_F2] as Array[int])
	assert_eq(_physical_keycodes(RTSController.CMD_SELECT_PRODUCTION), [KEY_F3] as Array[int])


func test_selectors_are_off_the_alphabetical_block() -> void:
	# The point of the F-row: a letter can never be both a verb and a selector again.
	for action: String in _SELECTOR_ACTIONS:
		for keycode: int in _physical_keycodes(action):
			assert_true(
				keycode >= KEY_F1 and keycode <= KEY_F12, "%s is bound to a function key" % action
			)


func test_no_selector_shares_a_key_with_the_command_grid() -> void:
	var grid_keys: Array[int] = []
	for action: StringName in _grid_actions():
		grid_keys.append_array(_physical_keycodes(String(action)))
	assert_false(grid_keys.is_empty(), "the grid has keys to compare against")
	for action: String in _SELECTOR_ACTIONS:
		for keycode: int in _physical_keycodes(action):
			assert_false(
				grid_keys.has(keycode), "%s does not share a key with a grid cell" % action
			)


func test_the_nine_letter_bound_selectors_are_gone() -> void:
	for action: String in _RETIRED_ACTIONS:
		assert_false(InputMap.has_action(action), "%s is retired" % action)


# --- The two broadening modifiers ---------------------------------------------


func test_the_broadening_modifiers_exist() -> void:
	assert_true(InputMap.has_action(RTSController.MODIFIER_NARROW))
	assert_true(InputMap.has_action(RTSController.MODIFIER_BROADEN))


func test_modifiers_are_not_command_prefixed() -> void:
	# RTSController._unhandled_input routes every "command_"-prefixed action a key press
	# triggers to _dispatch_command_hotkey. A modifier carrying that prefix would be
	# dispatched as a command in its own right — the same reason purchase_fallback isn't
	# called command_fallback.
	assert_false(RTSController.MODIFIER_NARROW.begins_with("command_"))
	assert_false(RTSController.MODIFIER_BROADEN.begins_with("command_"))


func test_modifiers_are_keyboard_only() -> void:
	# Constraint 1 in gdd/systems/ux/ui/interface-idioms.md — macOS turns
	# Ctrl+left-click into a right-click — only bites for modifiers applied to a CLICK.
	# These two modify an F-key, so Ctrl is available to them; this pins that neither is
	# bound to a mouse button.
	for action: String in [RTSController.MODIFIER_NARROW, RTSController.MODIFIER_BROADEN]:
		for event: InputEvent in InputMap.action_get_events(action):
			assert_true(event is InputEventKey, "%s is a key, not a mouse button" % action)


# --- The selectors have left the command grid ---------------------------------


func test_the_command_grid_holds_no_selectors() -> void:
	# Selectors were three SELECT-context cells in row 0, shown only while nothing was
	# selected — backwards, since a selector is reached for precisely when the current
	# selection is wrong. They are SelectorPanel now, and vacating row 0 is what frees it
	# for the production contexts.
	for binding: ControlBinding in CommandGrid.bindings():
		assert_ne(
			binding.control_context,
			ControlBinding.ControlContext.SELECT,
			"%s is not a grid binding any more" % binding.command_name
		)


func test_the_selector_panel_offers_one_button_per_family() -> void:
	# Three buttons, not nine: which set a button yields is decided by the modifiers held
	# while it is pressed, exactly as it is for the F-key.
	var panel_actions: Array[String] = []
	for entry: Array in SelectorPanel.FAMILIES:
		panel_actions.append(entry[2] as String)
	assert_eq(panel_actions, _SELECTOR_ACTIONS)


# --- The cycle ordering rule ---------------------------------------------------
##
## Least-recently-selected over whatever the modifier let through — extracted as a static so
## the RULE can be pinned without a live entity, the same treatment narrowed_index gets on
## the command side.
##
## Deliberately NOT idle-first: that precedence is absolute, so the cycle would never leave
## the idle set while one member was idle, and the unmodified press would become identical to
## modifier_narrow exactly whenever that modifier would have mattered. The filter belongs to
## the modifier; the order belongs here.


func test_an_empty_set_has_no_pick() -> void:
	assert_eq(RTSController.cycle_index([]), -1)


func test_the_least_recently_selected_member_is_taken() -> void:
	assert_eq(RTSController.cycle_index([50.0, 10.0, 90.0]), 1)


func test_repeated_picks_walk_the_whole_group_before_repeating() -> void:
	# Simulates pressing the key four times over three members: selecting bumps
	# last_selected_time, so each press must land somewhere new until the group is exhausted.
	var times: Array = [10.0, 20.0, 30.0]
	var picked: Array = []
	for press: int in 4:
		var index: int = RTSController.cycle_index(times)
		picked.append(index)
		times[index] = 100.0 + press
	assert_eq(picked, [0, 1, 2, 0], "every member once, then back to the front")


func test_a_busy_member_is_reachable() -> void:
	# The unmodified cycle takes ANY member. If it preferred idle ones, this member would be
	# unreachable while anything else was idle, and modifier_narrow would mean nothing.
	assert_eq(RTSController.cycle_index([5.0]), 0)
