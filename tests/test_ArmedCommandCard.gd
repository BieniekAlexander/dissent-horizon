extends GutTest

## The card's ARMED state: an order is held, so the grid stops being the selection's command
## card and becomes that order's own menu plus a way out.
##
## Three states, and the rules that separate them (see ui/control-matrices.md §Context 1a):
##   1. nothing armed              -> the ordinary card
##   2. armed, still choosing      -> PENDING: the builder's structure list (or a cargo
##                                   menu), and Cancel
##   3. armed and answered         -> READY: Cancel, plus the menu that answered it — still
##                                   on screen, so the pick can be changed
##
## Everything here reads the CONTROLLER's own state, so it runs on one that was never put in
## a scene tree — which also pins the guard that makes that possible: `command_message` is
## @onready and null off-tree, and "nothing armed" is the right answer then.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd \
##     -gtest=res://tests/test_ArmedCommandCard.gd -gexit


func _controller() -> RTSController:
	return autofree(RTSController.new()) as RTSController


#region What counts as armed
func test_a_bare_controller_is_not_armed() -> void:
	var controller: RTSController = _controller()
	assert_false(
		controller.is_command_armed(),
		"command_message is null off-tree, and that is not a reason to claim something is armed"
	)
	assert_false(controller.is_command_ready())


func test_a_pending_sub_mode_is_armed() -> void:
	var controller: RTSController = _controller()
	controller.pending_command_name = "command_attack_move"
	assert_true(controller.is_command_armed())


func test_an_armed_sanction_is_armed() -> void:
	var controller: RTSController = _controller()
	controller._pending_sanction = autofree(Sanction.new()) as Sanction
	assert_true(controller.is_command_armed())


#endregion


#region Armed but still choosing — state 2, not READY
## `command_ability` puts the card into the BUILD context, which is the builder's structure
## list. The player has armed a Build and not yet said what to build.
func test_a_build_with_no_tool_yet_is_not_ready() -> void:
	var controller: RTSController = _controller()
	controller.pending_command_name = "command_ability"
	assert_true(controller.is_command_armed(), "a Build IS armed")
	assert_false(
		controller.is_command_ready(), "but the card still has a question to ask — which structure?"
	)


## A sanction offering a cargo menu is the same shape: armed, unanswered.
func test_a_sanction_awaiting_its_payload_is_not_ready() -> void:
	var controller: RTSController = _controller()
	var sanction := autofree(Sanction.new()) as Sanction
	controller._pending_sanction = sanction
	if sanction.takes_a_payload():
		assert_false(controller.is_command_ready())
	else:
		# No payload to pick means nothing left to ask, which is state 3.
		assert_true(controller.is_command_ready())


#endregion


#region Armed and answered — state 3
## A verb that takes no tool is ready the moment it is armed: there is nothing to choose.
func test_a_toolless_verb_is_ready_at_once() -> void:
	var controller: RTSController = _controller()
	controller.pending_command_name = "command_attack_move"
	assert_true(controller.is_command_ready())


func test_a_toolless_verb_offers_only_cancel() -> void:
	# It asked nothing, so there is no menu to keep up beside the way out.
	var controller: RTSController = _controller()
	controller.pending_command_name = "command_attack_move"
	assert_eq(
		controller._visible_command_names(),
		[RTSController.CANCEL_COMMAND],
		"aiming is the only thing left to do, so it is the only thing offered"
	)


## THE RULE THIS FILE EXISTS FOR NOW: the menu does not close when it is answered. Picking
## the wrong structure used to leave the card holding one Cancel button, so changing your
## mind meant cancelling and re-opening the list — the pick is a radio button, not a door.
func test_the_build_menu_stays_up_while_the_build_is_armed() -> void:
	var controller: RTSController = _controller()
	controller.pending_command_name = "command_ability"
	assert_eq(
		controller.current_context(),
		ControlBinding.ControlContext.BUILD,
		"the fixture is in the build sub-menu"
	)
	# With no selection there are no tools to list, so what is pinned here is the SHAPE:
	# whatever the menu holds, Cancel is on the card beside it rather than instead of it.
	var names: Array = controller._visible_command_names()
	assert_true(names.has(RTSController.CANCEL_COMMAND), "the way out is always offered")
	assert_eq(names, controller.armed_card_menu() + [RTSController.CANCEL_COMMAND])


## Both readings of ARMED, and the fact that they are readings of ONE state rather than two
## cards: the card's contents follow the same rule either way.
func test_the_banner_distinguishes_pending_from_ready() -> void:
	var controller: RTSController = _controller()
	assert_eq(controller.armed_card_state(), CardModeBanner.ArmedState.NONE)
	controller.pending_command_name = "command_ability"
	assert_eq(
		controller.armed_card_state(),
		CardModeBanner.ArmedState.PENDING,
		"a Build with nothing chosen is still asking"
	)
	controller.pending_command_name = "command_attack_move"
	assert_eq(
		controller.armed_card_state(),
		CardModeBanner.ArmedState.READY,
		"a verb that takes no tool is answered the moment it is armed"
	)


func test_the_unarmed_card_does_not_show_cancel() -> void:
	var controller: RTSController = _controller()
	assert_false(
		controller._visible_command_names().has(RTSController.CANCEL_COMMAND),
		"there is nothing to put down"
	)


#endregion


#region Cancel
## Cancel is offered by the CONTROLLER's state rather than by the selection's capabilities,
## so it is available with nothing selected — a commander-card ordnance is armed that way.
func test_cancel_is_available_exactly_while_something_is_armed() -> void:
	var controller: RTSController = _controller()
	assert_false(controller._command_is_available(RTSController.CANCEL_COMMAND))
	controller.pending_command_name = "command_attack_move"
	assert_true(
		controller._command_is_available(RTSController.CANCEL_COMMAND),
		"and with an empty selection, which the ordinary availability gate would refuse"
	)


## ARMED, not answered. Needing to finish choosing a structure before you are allowed to
## cancel is absurd, and it is what gating this on is_command_ready() used to do.
func test_cancel_is_available_while_still_choosing() -> void:
	var controller: RTSController = _controller()
	controller.pending_command_name = "command_ability"
	assert_false(controller.is_command_ready(), "the fixture is mid-question")
	assert_true(controller._command_is_available(RTSController.CANCEL_COMMAND))


func test_disarming_puts_down_every_armed_thing_at_once() -> void:
	var controller: RTSController = _controller()
	controller.pending_command_name = "command_ability"
	controller._pending_sanction = autofree(Sanction.new()) as Sanction
	controller.disarm_command()
	assert_eq(controller.pending_command_name, "")
	assert_null(controller._pending_sanction)
	assert_false(controller.is_command_armed())


## Cancelling says nothing about what is selected — it is a statement about the ORDER.
func test_disarming_leaves_the_selection_alone() -> void:
	var controller: RTSController = _controller()
	var unit := add_child_autofree(Node.new()) as Node
	controller.selection = [unit] as Array[Node]
	controller.pending_command_name = "command_attack_move"
	controller.disarm_command()
	assert_eq(controller.selection, [unit] as Array[Node])


#endregion


#region The Cancel button's cell
## Bottom-right of a 6x3 grid, whose positional hotkey is already N — so the "give it the N
## key" half of the request needed no new action at all.
func test_cancel_sits_bottom_right() -> void:
	var binding: ControlBinding = CommandGrid.binding_for(RTSController.CANCEL_COMMAND)
	assert_not_null(binding, "the Cancel button has a binding")
	assert_eq(
		binding.grid_position,
		Vector2i(ControlBinding.GRID_WIDTH - 1, ControlBinding.GRID_HEIGHT - 1)
	)


func test_its_cell_hotkey_is_n() -> void:
	var action: StringName = ControlBinding.cell_action(
		Vector2i(ControlBinding.GRID_WIDTH - 1, ControlBinding.GRID_HEIGHT - 1)
	)
	assert_true(InputMap.has_action(action), "the cell has an action")
	var keys: Array = InputMap.action_get_events(action).filter(
		func(e: InputEvent) -> bool: return e is InputEventKey
	)
	assert_false(keys.is_empty(), "and the action is bound to a key")
	assert_eq((keys[0] as InputEventKey).physical_keycode, KEY_N)


## It is drawn ahead of anything else claiming its cell, so it is never AMBIGUOUS with them
## — which is why the collision review skips it rather than reporting it against whatever
## else wants (5, 2). Nothing does: no tool is laid out in column 5 at all.
func test_it_is_exempt_from_the_collision_review() -> void:
	var binding: ControlBinding = CommandGrid.binding_for(RTSController.CANCEL_COMMAND)
	assert_true(binding.wins_its_cell())
	for collision: String in ControlBinding.grid_collisions(CommandGrid.bindings()):
		assert_false(
			collision.contains(RTSController.CANCEL_COMMAND),
			"a button drawn alone cannot collide: %s" % collision
		)


#endregion


#region The Repair button
## `H` for "heal" is only the mnemonic the cell's key gives it. The word on the button is
## REPAIR, because one order mends a dented tank and a burning barracks alike and the
## Colonials' Servants work on BIO and MECH frames both — "heal" names half of it.
func test_repair_sits_in_the_h_cell() -> void:
	var binding: ControlBinding = CommandGrid.binding_for("command_repair")
	assert_not_null(binding, "Repair has a grid button")
	assert_eq(binding.grid_position, Vector2i(5, 1))
	assert_eq(binding.label, "Repair")


func test_the_h_cells_hotkey_is_h() -> void:
	var action: StringName = ControlBinding.cell_action(Vector2i(5, 1))
	assert_true(InputMap.has_action(action))
	var keys: Array = InputMap.action_get_events(action).filter(
		func(e: InputEvent) -> bool: return e is InputEventKey
	)
	assert_false(keys.is_empty())
	assert_eq((keys[0] as InputEventKey).physical_keycode, KEY_H)


## Arming it must reach the same command a right-click on a damaged friendly resolves, or
## the button would be a second, weaker route to the same order.
func test_arming_it_resolves_the_repair_command() -> void:
	assert_eq(RTSController.HOTKEY_COMMANDS.get("command_repair"), Repair)
