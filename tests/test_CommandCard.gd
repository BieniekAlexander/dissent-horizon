extends GutTest

## The command grid's TWO CARDS — ControlBinding.CommandFamily — and the positional
## hotkeys that read them.
##
## The whole point of the split is that a command belongs to a CARD rather than to an
## entity kind, so a structure that both shoots and trains reaches both sets of orders
## through the toggle. These tests work on the classification and on the pure lookups
## (ControlBinding / CommandGrid); the controller's own state machine is exercised through
## the small slice of it that needs no scene tree.

## --- Cards ------------------------------------------------------------------


func test_the_verbs_are_all_on_the_active_card() -> void:
	for command_name: String in [
		"command_attack_move",
		"command_stop",
		"command_defend",
		"command_move",
		"command_focus_fire",
		"command_evacuate",
		"command_launch",
		"command_land",
		"command_ability"
	]:
		var binding: ControlBinding = CommandGrid.binding_for(command_name)
		assert_not_null(binding, command_name)
		assert_eq(binding.family, ControlBinding.CommandFamily.ACTIVE, command_name)


## Build is deliberately ACTIVE even though placing a structure is production in the
## economic sense: it is an order given to a unit, mid-fight, beside that unit's other
## orders. Moving it would mean flipping cards to tell a builder what to do.
func test_build_and_its_structure_list_stay_on_the_active_card() -> void:
	assert_eq(
		CommandGrid.binding_for("command_ability").family, ControlBinding.CommandFamily.ACTIVE
	)
	for tool: Tool in Tool.command_tool_map.values():
		if (tool.control_context & ControlBinding.ControlContext.BUILD) != 0:
			assert_eq(tool.family, ControlBinding.CommandFamily.ACTIVE, tool.command_name)


func test_training_is_the_production_card() -> void:
	var seen: int = 0
	for tool: Tool in Tool.command_tool_map.values():
		if (tool.control_context & ControlBinding.ControlContext.TRAIN) != 0:
			assert_eq(tool.family, ControlBinding.CommandFamily.PRODUCTION, tool.command_name)
			seen += 1
	assert_gt(seen, 0, "there are train tools to check")


## --- Row idioms -------------------------------------------------------------
##
## A cell's row says what KIND of thing lives there before the player reads the button.
## Row 1 is the generic verbs on the ACTIVE card and training on the PRODUCTION one; the
## ability rows are 0 and 2.


func test_the_generic_verbs_occupy_row_one() -> void:
	# A S D F G: the orders every unit answers to. Evacuate used to sit at F and does not
	# belong here — it needs a garrison, so it is an ability of whatever owns one.
	for command_name: String in [
		"command_attack_move",
		"command_stop",
		"command_defend",
		"command_focus_fire",
		"command_move"
	]:
		assert_eq(CommandGrid.binding_for(command_name).grid_position.y, 1, command_name)


func test_unit_abilities_are_off_the_verb_row() -> void:
	# Radiate, Land and Evacuate belong to whichever pieces happen to carry the component
	# behind them, so they are abilities rather than orders every unit answers to.
	for command_name: String in [
		"command_launch", "command_land", "command_ability", "command_evacuate"
	]:
		assert_ne(CommandGrid.binding_for(command_name).grid_position.y, 1, command_name)


## Row 0 of the PRODUCTION card belongs to the producer-context switcher, and to nothing else.
## It was held EMPTY by this test until the switcher was built; now it is held EXCLUSIVE,
## which is the same guarantee for the same reason — a train button landing there would take a
## cell whose key players have learned means "show me this producer's line".
func test_the_production_context_row_holds_only_contexts() -> void:
	var contexts: int = 0
	for binding: ControlBinding in CommandGrid.bindings():
		if (
			binding.family != ControlBinding.CommandFamily.PRODUCTION
			or binding.grid_position.y != 0
		):
			continue
		assert_true(
			binding is ProducerContextBinding,
			"%s is not squatting in the context row" % binding.command_name
		)
		contexts += 1
	assert_gt(contexts, 0, "the row is populated")


## --- Positional hotkeys -----------------------------------------------------


## A command has no key of its own — it has a cell, and the cell has the key. This is what
## makes one key mean different things on the two cards, and it is the property the whole
## family gate rests on.
func test_a_command_resolves_to_the_key_of_the_cell_it_occupies() -> void:
	assert_eq(
		CommandGrid.action_for_command("command_attack_move"),
		ControlBinding.cell_action(Vector2i(0, 1))
	)
	assert_eq(InputPrompt.action_text(CommandGrid.action_for_command("command_attack_move")), "A")
	assert_eq(InputPrompt.action_text(CommandGrid.action_for_command("command_stop")), "S")


## The same key, on the two cards, reaches two different commands. Asserted on the data the
## dispatcher reads rather than by driving input: cell (0, 1) is attack-move among the
## ACTIVE bindings and a train tool among the PRODUCTION ones.
func test_one_cell_carries_a_command_on_each_card() -> void:
	var cell := Vector2i(0, 1)
	var by_family: Dictionary = {}
	for binding: ControlBinding in CommandGrid.bindings():
		if binding.grid_position == cell:
			by_family[binding.family] = true
	assert_true(by_family.has(ControlBinding.CommandFamily.ACTIVE), "combat command at (0, 1)")
	assert_true(by_family.has(ControlBinding.CommandFamily.PRODUCTION), "train command at (0, 1)")


func test_a_command_with_no_button_has_no_key() -> void:
	# These are resolved by right-clicking, never pressed. command_embark is deliberately
	# among them: it names its subject by hovering it, so a button could not say who.
	for command_name: String in [
		"command_attack", "command_interact", "command_occupy", "command_embark"
	]:
		assert_eq(CommandGrid.action_for_command(command_name), &"", command_name)


## Copy goes on naming commands (`{{ command_attack_move }}`) after the move to positional
## hotkeys, because InputPrompt resolves a command through its cell. Without this every
## tooltip and dialog naming a verb would render literal braces.
func test_copy_can_still_name_a_command() -> void:
	assert_eq(InputPrompt.format("attack-move is {{ command_attack_move }}"), "attack-move is A")
	assert_eq(InputPrompt.format("halt with {{ command_stop }}"), "halt with S")


## --- The toggle -------------------------------------------------------------


func test_the_card_toggle_is_bound_and_is_not_a_command() -> void:
	assert_true(InputMap.has_action("card_toggle_family"))
	# The dispatcher routes every "command_"-prefixed action into the grid; flipping the
	# card is not a command the selection carries out.
	assert_false("card_toggle_family".begins_with("command_"))


func test_the_toggle_key_is_not_also_a_grid_cell() -> void:
	var toggle_keys: Array = []
	for event: InputEvent in InputMap.action_get_events("card_toggle_family"):
		var key := event as InputEventKey
		if key != null:
			toggle_keys.append(key.physical_keycode)
	assert_eq(toggle_keys, [KEY_TAB])
	for action: StringName in ControlBinding.cell_actions():
		for event: InputEvent in InputMap.action_get_events(action):
			var key := event as InputEventKey
			if key != null:
				assert_false(
					toggle_keys.has(key.physical_keycode),
					"%s does not collide with the card toggle" % action
				)


## --- Which card a selection opens on ----------------------------------------
##
## A live-ish slice: `_settle_command_family` reads nothing but `selection` and
## `_available_commands`, so it runs on a bare controller that was never put in a tree.

## Fakes: a stationary producer of one trainee, a soldier, a producer that also casts, and a gun.
const BARRACKS: Dictionary = {"structure": true, "produces": [&"fake_trainee"]}
const RECRUIT: Dictionary = {"speed": 2.0, "weapon": {"ground": 6.0}}


## A controller that was never put in a scene tree — the card rules read nothing but
## `selection` and `_available_commands`. The empty CommandsView is the one exception: the
## repaint `set_command_family` triggers addresses it with `$`, so it is REQUIRED rather than
## optional, and a fixture that skips it is testing against a node the game always has.
func _controller(a_selection: Array) -> RTSController:
	var controller := autofree(RTSController.new()) as RTSController
	var section := Control.new()
	section.name = "CommandsSection"
	var border := Control.new()
	border.name = "CommandsBorder"
	var view := Control.new()
	view.name = "CommandsView"
	border.add_child(view)
	section.add_child(border)
	controller.add_child(section)
	controller.selection.assign(a_selection)
	controller._available_commands = CommandContextParser.commands_for_selection(a_selection)
	controller._settle_command_family()
	return controller


## Live entities, owned but mapless: entering the tree is what resolves their components,
## and the card decision reads nothing else. Loaded rather than preloaded — a file-scope
## preload of an entity scene fires Tool's static registry initialiser at parse time and
## makes Tool.for_name null for the whole run (see CLAUDE.md).
func before_each() -> void:
	FakePieces.register_tool(
		FakePieces.tool(
			&"fake_trainee",
			FakePieces.PLAIN,
			[],
			ControlBinding.ControlContext.TRAIN,
			[&"fake_barracks"]
		)
	)
	FakePieces.install_ability(
		&"bombard", {"command": "command_bombard", "grid": [0, 0], "range": 30.0}
	)


func after_each() -> void:
	FakePieces.restore_tools()
	FakePieces.restore_abilities()


func _entity(a_options: Dictionary) -> Commandable:
	var commander := Commander.new()
	commander.id = 1
	add_child_autofree(commander)
	var entity := FakePieces.make(a_options) as Commandable
	add_child_autofree(entity)
	entity.ownership.commander = commander
	return entity


## The regression: a producer's rally is a bare `command_move`, and giving the plain move a
## cell of its own made every barracks report a ACTIVE command. Preferring ACTIVE for that
## put a lone Go button where the training used to be and hid every train button behind the
## toggle.
func test_a_stationary_producer_opens_on_its_training() -> void:
	var barracks: Commandable = _entity(BARRACKS)
	assert_false(barracks.has_node("Locomotion"), "guards the fixture: a barracks is stationary")
	var controller: RTSController = _controller([barracks])
	assert_eq(controller.command_family, ControlBinding.CommandFamily.PRODUCTION)
	assert_gt(controller._visible_command_names().size(), 0, "and has buttons to draw")


func test_a_unit_opens_on_the_active_card() -> void:
	assert_eq(_controller([_entity(RECRUIT)]).command_family, ControlBinding.CommandFamily.ACTIVE)


## A group picked up mid-fight is picked up to be ORDERED, even when a structure came along
## with it — having to press a key before you can tell it to move is a tax on the common
## case to serve the rare one.
func test_a_mixed_selection_opens_on_the_active_card() -> void:
	assert_eq(
		_controller([_entity(BARRACKS), _entity(RECRUIT)]).command_family,
		ControlBinding.CommandFamily.ACTIVE
	)


## --- The ability bar reaches past the card ----------------------------------

## The sanction/ability bar is a SHORTCUT to a grid button: it replaces the selection with
## the ability's casters and arms the command. But replacing the selection re-settles the
## card, and a Citadel — an immobile producer that also carries abilities — settles on
## PRODUCTION, while the ability it was pressed for is drawn on ACTIVE. `_command_is_available`
## refuses a command the visible card is not drawing, so the button selected the casters and
## then silently did nothing. `_show_card_for_command` is what closes that.
const CITADEL: Dictionary = {
	"structure": true, "produces": [&"fake_trainee"], "abilities": [{"grants": [&"bombard"]}]
}
const CANNON: Dictionary = {"structure": true, "abilities": [{"grants": [&"bombard"]}]}


func test_a_producer_that_also_carries_abilities_settles_on_production() -> void:
	# Guards the fixture for the test below: this is the selection that exposed the gap.
	var citadel: Commandable = _entity(CITADEL)
	assert_true(citadel.has_node("Production"), "it trains")
	assert_true(citadel.has_node("Abilities"), "and it casts")
	assert_eq(_controller([citadel]).command_family, ControlBinding.CommandFamily.PRODUCTION)


## A Citadel selected beside a Cannon: the Citadel trains (PRODUCTION), the Cannon carries the
## bombard battery (ACTIVE), and neither moves — so the card settles on PRODUCTION while the
## ability the bar was pressed for is drawn on the other one.
## A Citadel selected beside a Cannon: the Citadel trains (PRODUCTION), the Cannon carries the
## bombard battery — which is an ORDNANCE, on the commander's card — and neither moves, so the
## card settles on PRODUCTION while the ability the bar was pressed for is drawn elsewhere.
func test_arming_a_command_turns_the_grid_to_its_card() -> void:
	var controller: RTSController = _controller([_entity(CITADEL), _entity(CANNON)])
	assert_eq(
		controller.command_family,
		ControlBinding.CommandFamily.PRODUCTION,
		"guards the fixture: it starts on another card"
	)
	controller._show_card_for_command("command_bombard")
	assert_eq(controller.command_family, ControlBinding.CommandFamily.ORDNANCE)
	assert_true(
		controller._command_is_available("command_bombard"),
		"and the command the bar armed can now actually be issued"
	)


func test_turning_to_a_card_the_selection_cannot_fill_is_refused() -> void:
	# set_command_family is what keeps _show_card_for_command from emptying the grid.
	var recruit: Commandable = _entity(RECRUIT)
	var controller: RTSController = _controller([recruit])
	assert_eq(controller.command_family, ControlBinding.CommandFamily.ACTIVE)
	controller._show_card_for_command("command_tool_fake_trainee")
	assert_eq(
		controller.command_family,
		ControlBinding.CommandFamily.ACTIVE,
		"a soldier has no production card to turn to"
	)


## --- Leaving the commander's card -------------------------------------------
##
## ORDNANCE is not about the selection, so nothing about the selection may settle ONTO it —
## but two things take you OFF it, and both had to be asked for after the first build shipped
## them wrong.


func test_tab_off_the_ordnance_card_lands_on_active_even_with_nothing_selected() -> void:
	# It used to REFUSE here (ACTIVE has nothing to draw for an empty selection), which left
	# the player on ORDNANCE unsure whether the key had registered. Landing on an empty ACTIVE
	# hides the panel, which is the close gesture.
	var controller: RTSController = _controller([])
	controller.set_command_family(ControlBinding.CommandFamily.ORDNANCE)
	assert_eq(
		controller.command_family,
		ControlBinding.CommandFamily.ORDNANCE,
		"the commander's card is always enterable"
	)
	controller.toggle_command_family()
	assert_eq(controller.command_family, ControlBinding.CommandFamily.ACTIVE)


func test_tab_off_the_ordnance_card_prefers_the_selections_own_card() -> void:
	var controller: RTSController = _controller([_entity(BARRACKS)])
	controller.set_command_family(ControlBinding.CommandFamily.ORDNANCE)
	controller.toggle_command_family()
	assert_eq(
		controller.command_family,
		ControlBinding.CommandFamily.PRODUCTION,
		"a barracks was picked up to be told what to make"
	)


## Selecting something with no ordnances of its own is an act of "I want to command THIS", and
## the card follows. Selecting nothing is not — deselecting must not kick the player off a card
## that was never about the selection.
func test_selecting_a_piece_with_no_ordnances_leaves_the_commander_card() -> void:
	var controller: RTSController = _controller([])
	controller.set_command_family(ControlBinding.CommandFamily.ORDNANCE)
	controller.selection.assign([_entity(RECRUIT)])
	controller.available_commands = CommandContextParser.commands_for_selection(
		controller.selection
	)
	assert_eq(controller.command_family, ControlBinding.CommandFamily.ACTIVE)


func test_an_empty_selection_leaves_the_commander_card_alone() -> void:
	var controller: RTSController = _controller([])
	controller.set_command_family(ControlBinding.CommandFamily.ORDNANCE)
	controller.available_commands = []
	assert_eq(controller.command_family, ControlBinding.CommandFamily.ORDNANCE)


## The masked view is what keeps every card-CHOOSING path off the commander's card, while the
## unmasked one is what the settle above consults to ask whether the new selection has
## ordnances of its own.
func test_the_commander_card_is_never_offered_to_a_chooser() -> void:
	var controller: RTSController = _controller([_entity(RECRUIT)])
	assert_eq(controller.selection_owned_families() & ControlBinding.CommandFamily.ORDNANCE, 0)
