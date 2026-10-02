extends GutTest

## The input map itself: the actions the control scheme names must exist, the retired ones
## must be gone, and the one name that breaks the prefix convention must stay routed
## around the hotkey dispatcher.
##
## Why these exist: gdd/systems/ux/ui/input-action-naming.md. An InputMap action is looked up
## by STRING from a dozen call sites and from scene-authored `{{ }}` copy, so a rename that
## misses one fails silently — the branch simply never fires, and nothing errors.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_InputActions.gd -gexit


func test_the_renamed_actions_exist() -> void:
	for action: StringName in [&"modifier_additive", &"world_select", &"command_issue"]:
		assert_true(InputMap.has_action(action), "%s is bound" % action)


func test_the_old_names_are_gone() -> void:
	# Not cosmetic: a leftover definition would keep answering `is_action_pressed` for a
	# call site the rename missed, hiding the miss until a rebinding screen exposed it.
	for action: StringName in [&"command_additive", &"isometric_camera_select", &"move"]:
		assert_false(InputMap.has_action(action), "%s was renamed away" % action)


func test_the_requisition_toggle_is_retired() -> void:
	# Requisition is the additive modifier now; the toggle, its key and its HUD indicator
	# all went together. A surviving key would be a second, silent way into the mode.
	assert_false(InputMap.has_action(&"purchase_requisition"))


func test_the_three_modifiers_share_one_prefix() -> void:
	# The prefix is the convention that keeps a modifier out of the command dispatcher.
	for action: StringName in [&"modifier_additive", &"modifier_narrow", &"modifier_broaden"]:
		assert_true(InputMap.has_action(action), "%s is bound" % action)
		assert_true(String(action).begins_with("modifier_"), "%s is named as a modifier" % action)


func test_the_additive_modifier_is_reachable_through_the_controller_constant() -> void:
	# The string used to be written as a literal in seven files, which is what made the
	# rename a text sweep. One constant is the fix, and it has to name a REAL action.
	assert_true(InputMap.has_action(StringName(RTSController.MODIFIER_ADDITIVE)))


## `command_issue` is the one action whose name breaks the prefix rule: `command_*` means
## "routed to the grid hotkey dispatcher", and this is a pointer button. It is handled by
## an explicit branch placed ABOVE the prefix test in RTSController._unhandled_input. If
## that branch is ever moved below it, right-click stops issuing orders and starts pressing
## whatever sits in a command cell — silently, because both paths are legal code.
func test_command_issue_is_not_a_grid_cell_action() -> void:
	assert_eq(
		ControlBinding.position_from_action("command_issue"),
		Vector2i(-1, -1),
		"it must not resolve to a grid cell"
	)


func test_command_issue_is_handled_before_the_prefix_branch() -> void:
	var source: String = FileAccess.get_file_as_string("res://scripts/interface/rts_controller.gd")
	assert_ne(source, "", "the controller source is readable")
	var explicit: int = source.find('is_action_pressed("command_issue")')
	# The dispatcher is matched by a REGEX that skips whatever the event argument is
	# called. Pinning the parameter's name made this test fail the day the controller's
	# parameters took the `a_` prefix — a naming change, not the ordering this is about.
	var dispatcher := RegEx.create_from_string('get_action_names_by_prefix\\([^,]+, "command_"\\)')
	var match_found: RegExMatch = dispatcher.search(source)
	var prefix: int = match_found.get_start() if match_found != null else -1
	assert_gt(explicit, -1, "the explicit branch exists")
	assert_gt(prefix, -1, "the prefix dispatcher exists")
	assert_lt(explicit, prefix, "and the explicit branch comes first")
