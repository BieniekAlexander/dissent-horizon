extends GutTest

## ControlBinding: the grid placement math + collision review shared by every grid
## command (verbs and Tools). The collision review runs over the WHOLE grid —
## CommandGrid.bindings() (verbs + tools) — so verb↔tool overlaps are reviewed too,
## not just tool↔tool.

func test_cell_index_is_row_major() -> void:
	assert_eq(ControlBinding.cell_index(Vector2i(0, 0)), 0)
	assert_eq(ControlBinding.cell_index(Vector2i(1, 0)), 1)
	assert_eq(ControlBinding.cell_index(Vector2i(0, 1)), ControlBinding.GRID_WIDTH)
	assert_eq(ControlBinding.cell_index(Vector2i(2, 1)), ControlBinding.GRID_WIDTH + 2)

func test_position_in_bounds() -> void:
	assert_true(ControlBinding.position_in_bounds(Vector2i(0, 0)))
	assert_true(ControlBinding.position_in_bounds(Vector2i(ControlBinding.GRID_WIDTH - 1, ControlBinding.GRID_HEIGHT - 1)))
	assert_false(ControlBinding.position_in_bounds(Vector2i(-1, 0)))
	assert_false(ControlBinding.position_in_bounds(Vector2i(ControlBinding.GRID_WIDTH, 0)))
	assert_false(ControlBinding.position_in_bounds(Vector2i(0, ControlBinding.GRID_HEIGHT)))

func test_base_binding_faction_mask_is_all_factions() -> void:
	# A plain (verb) binding is faction-agnostic: all-ones, so faction can never be
	# what separates it from a tool in the collision review.
	var verb := ControlBinding.new("command_stop", "Stop", Vector2i(1, 1), ControlBinding.ControlContext.ACT)
	assert_eq(verb.faction_mask(), ControlBinding.FACTION_ANY)

func test_all_grid_positions_in_bounds() -> void:
	# Hard invariant across the WHOLE grid: every button must fit, else CommandGrid
	# can't place it.
	assert_eq(ControlBinding.out_of_bounds(CommandGrid.bindings()), [],
		"all grid positions valid")

## Review gate over the whole grid: any cell overlap between bindings that could appear
## together must be listed here, having been reviewed and judged acceptable. A NEW unlisted
## collision fails this test — review it, then move a binding or acknowledge it here.
##
## Most overlaps never reach this list, because grid_collisions() knows four things that
## keep two buttons apart: they are on different CARDS, in different CONTEXTS (an ACT verb
## vs a BUILD tool), belong to different FACTIONS, or are offered by disjoint sets of
## ACTORS. That last one is what lets every faction's training row fit in six columns —
## a barracks' infantry and an airfield's aircraft both start at column 0 and no selection
## is ever asked to draw both.
## The technocracy roster used to carry two generations of the same buildings: the
## original prototype set (dwelling / compound / lab / armory) and the later
## faction-generic tc_* set, which named the same ROLES and so landed in the same
## cells — acknowledged here as a known collision. That's resolved now: `compound`
## was renamed to `tc_barracks` (the id the empty tc_* skeleton had been squatting
## on), and `dwelling` / `tc_infrastructure` were deleted outright rather than picking a
## survivor (see gdd/id-rename-proposal.md), so there is only one tool per cell.
const _ACKNOWLEDGED_COLLISIONS: Array = []

func test_grid_collisions_are_all_acknowledged() -> void:
	assert_eq(ControlBinding.grid_collisions(CommandGrid.bindings()), _ACKNOWLEDGED_COLLISIONS,
		"unreviewed grid collision(s) — move a binding or add to _ACKNOWLEDGED_COLLISIONS")

## Every button in the grid — verb, selector and tool alike — says something on hover.
## The verbose tier stays optional (a one-line command has nothing longer to say), but the
## simple one is the contract VerboseTooltipButton enforces at runtime, and this is where
## a new binding that forgot it gets caught before a player finds the TODO placeholder.
func test_every_binding_carries_a_simple_tooltip() -> void:
	for binding: ControlBinding in CommandGrid.bindings():
		assert_false(binding.simple_tooltip.strip_edges().is_empty(),
			"%s has a simple tooltip" % binding.command_name)

## The copy names its keys with `{{ action }}` placeholders, resolved when the button is
## built (see ButtonSpec / InputPrompt). A placeholder that resolves to nothing would ship
## literal braces to the player.
##
## Resolution accepts an InputMap action OR a grid command name, since a grid command has
## no action of its own — the CELL carries the key (see below), so `{{ command_attack_move }}`
## resolves through whichever cell that button currently occupies.
func test_tooltip_placeholders_resolve() -> void:
	for binding: ControlBinding in CommandGrid.bindings():
		for text: String in [binding.simple_tooltip, binding.verbose_tooltip]:
			for name: StringName in InputPrompt.referenced_actions(text):
				assert_ne(InputPrompt.resolve_action(name), &"",
					"%s references '%s'" % [binding.command_name, name])

#region Positional hotkeys
## Hotkeys name a CELL, not a command: cell (x, y) answers to `command_cell_x_y`, and what
## the key does is whatever that cell is currently drawing. project.godot has to carry one
## action per cell, or part of the grid is silently unreachable from the keyboard.
func test_every_grid_cell_has_an_input_action() -> void:
	for action: StringName in ControlBinding.cell_actions():
		assert_true(InputMap.has_action(action), "project.godot defines '%s'" % action)
		assert_false(InputMap.action_get_events(action).is_empty(),
			"'%s' has a key bound" % action)

## The default layout is the left hand: `QWERTY / ASDFGH / ZXCVBN`, read row-major. Only a
## default — the point of naming actions after cells is that a rebinding screen can rewrite
## them — but a mis-typed keycode in project.godot is invisible until someone plays.
func test_default_cell_keys_follow_the_keyboard_rows() -> void:
	var rows: Array = ["QWERTY", "ASDFGH", "ZXCVBN"]
	for y in ControlBinding.GRID_HEIGHT:
		for x in ControlBinding.GRID_WIDTH:
			assert_eq(
				InputPrompt.action_text(ControlBinding.cell_action(Vector2i(x, y))),
				(rows[y] as String)[x],
				"cell (%d, %d)" % [x, y]
			)

func test_cell_action_round_trips_through_its_position() -> void:
	for y in ControlBinding.GRID_HEIGHT:
		for x in ControlBinding.GRID_WIDTH:
			var position := Vector2i(x, y)
			assert_eq(ControlBinding.position_from_action(
				String(ControlBinding.cell_action(position))), position)

## Anything that isn't a cell action must report as one, or the dispatcher would read a
## position out of an unrelated `command_` action (the selectors share that prefix).
func test_non_cell_actions_have_no_position() -> void:
	for name: String in ["command_select_army", "modifier_additive", "", "command_cell_",
			"command_cell_9_9", "command_cell_x_1"]:
		assert_eq(ControlBinding.position_from_action(name), Vector2i(-1, -1), name)
#endregion

#region Command families
## A binding is drawn on exactly one card, and which one follows from what it does rather
## than from a field someone remembered to set: verbs and structure placement are ACTIVE,
## training is PRODUCTION, an ability with global reach is ORDNANCE.
func test_every_binding_declares_one_family() -> void:
	var cards: Array[int] = [ControlBinding.CommandFamily.ACTIVE,
		ControlBinding.CommandFamily.PRODUCTION, ControlBinding.CommandFamily.ORDNANCE]
	for binding: ControlBinding in CommandGrid.bindings():
		assert_true(cards.has(binding.family),
			"%s is on exactly one card (got %d)" % [binding.command_name, binding.family])


## An ability's home is the commander's card. One may ALSO claim a cell on ACTIVE, where it is
## an order you give a selected piece — the Bombard is both — and that is a second binding
## rather than a second family on one, because the two cards have different neighbours.
func test_an_ability_binding_is_on_the_ordnance_card_or_the_active_one() -> void:
	var on_ordnance: int = 0
	for binding: ControlBinding in CommandGrid.bindings():
		if not (binding is AbilityBinding):
			continue
		assert_true(binding.family == ControlBinding.CommandFamily.ORDNANCE \
			or binding.family == ControlBinding.CommandFamily.ACTIVE, binding.command_name)
		if binding.family == ControlBinding.CommandFamily.ORDNANCE:
			on_ordnance += 1
	assert_gt(on_ordnance, 0, "the commander's card has buttons")

func test_tools_take_their_family_from_their_context() -> void:
	for tool: Tool in Tool.command_tool_map.values():
		var expected: int = ControlBinding.CommandFamily.PRODUCTION \
			if (tool.control_context & ControlBinding.ControlContext.TRAIN) != 0 \
			else ControlBinding.CommandFamily.ACTIVE
		assert_eq(tool.family, expected, tool.command_name)

## Row 1 of the PRODUCTION card is the training row (see CommandGrid's row idioms). A train
## button anywhere else is drawn where the player has learned to expect something else.
func test_train_tools_all_sit_in_the_training_row() -> void:
	# PRODUCTION card rows: training on row 1, research on row 2
	# (gdd/systems/ux/ui/command-card-and-hotkeys.md §Three cards, two keys).
	for tool: Tool in Tool.command_tool_map.values():
		if (tool.control_context & ControlBinding.ControlContext.TRAIN) == 0:
			continue
		if tool.is_upgrade:
			assert_eq(tool.grid_position.y, 2, "%s is in the research row" % tool.command_name)
		else:
			assert_eq(tool.grid_position.y, 1, "%s is in the training row" % tool.command_name)
#endregion
