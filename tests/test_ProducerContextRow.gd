extends GutTest

## Row 0 of the PRODUCTION card: one radio button per producer TYPE in the selection, picking
## whose training the card is showing.
##
## The design decision these pin is that a context cell is a STATIC property of a piece
## (`ui.context_grid`) rather than packed left per selection. Packing would move a war
## factory's button from W to Q depending on what else was picked up, and a key that trains one
## thing in one selection and another in the next is what positional hotkeys exist to prevent.

const CITADEL: String = "res://scenes/entities/structures/cl/cl_commandCenter.tscn"
const BARRACKS: String = "res://scenes/entities/structures/cl/cl_barracks.tscn"
const FACTORY: String = "res://scenes/entities/structures/cl/cl_warFactory.tscn"
const RECRUIT: String = "res://scenes/entities/units/cl/cl_bioLight_antiLight.tscn"


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
	controller.available_commands = CommandContextParser.commands_for_selection(a_selection)
	return controller


func _entity(a_scene: String) -> Commandable:
	var commander := Commander.new()
	commander.id = 1
	add_child_autofree(commander)
	var entity := (load(a_scene) as PackedScene).instantiate() as Commandable
	add_child_autofree(entity)
	entity.ownership.commander = commander
	return entity


# --- The cells are authored and static --------------------------------------------

func test_every_producer_authors_a_context_cell() -> void:
	var producers: Dictionary = {}
	for tool: Tool in Tool.command_tool_map.values():
		for producer: Variant in tool.producers:
			producers[StringName(str(producer))] = true
	assert_gt(producers.size(), 0, "guards the fixture")
	for id: StringName in producers:
		var piece: Tool = Tool.for_id(id)
		assert_not_null(piece, id)
		assert_ne(piece.context_grid, Vector2i(-1, -1),
			"%s is a producer, so it needs a row-0 cell" % id)


## The context cell is a SECOND cell — `grid` is where the piece's own build button sits on a
## builder's menu, which is a different button in a different list.
func test_the_context_cell_is_not_the_build_cell() -> void:
	var barracks: Tool = Tool.for_id(&"cl_barracks")
	assert_ne(barracks.context_grid, barracks.grid_position)


## Left-aligned COLLECTIVELY across a faction, which is an authoring convention and not a
## layout rule: the Citadel, Barracks, War Factory and Airfield take Q W E R between them.
func test_a_factions_producers_are_left_aligned_together() -> void:
	var cells: Array[int] = []
	for id: StringName in [&"cl_commandCenter", &"cl_barracks", &"cl_warFactory",
			&"cl_airField"]:
		var piece: Tool = Tool.for_id(id)
		assert_eq(piece.context_grid.y, 0, "%s is in row 0" % id)
		cells.append(piece.context_grid.x)
	assert_eq(cells, [0, 1, 2, 3] as Array[int])


func test_every_context_binding_is_on_the_production_card_row_zero() -> void:
	var seen: int = 0
	for binding: ControlBinding in CommandGrid.bindings():
		if not (binding is ProducerContextBinding):
			continue
		seen += 1
		assert_eq(binding.family, ControlBinding.CommandFamily.PRODUCTION)
		assert_eq(binding.grid_position.y, 0, binding.command_name)
	assert_gt(seen, 0, "the row has buttons")


## A context button acts on the CARD, so it must not carry the `command_` prefix that routes
## an action into the grid's dispatcher as an order to the selection.
func test_a_context_button_is_not_a_command() -> void:
	assert_false(ProducerContextBinding.PREFIX.begins_with("command_"))


# --- The row appears only when there is a choice ----------------------------------

## A single producer still draws its button, greyed as the radio already set. A row that
## appeared only for two kinds of producer would come and go under the player's hand.
func test_one_producer_selected_still_draws_its_button() -> void:
	var controller: RTSController = _controller([_entity(BARRACKS)])
	assert_eq(controller.producer_context_names().size(), 1)
	var current: String = ProducerContextBinding.PREFIX + String(controller.producer_context())
	assert_eq(CommandButtonState.of(current, controller.selection, null, false, current).blocker,
		CommandButtonState.Blocker.CURRENT, "and it is the greyed, unpressable one")


func test_two_producer_types_draw_the_row() -> void:
	var controller: RTSController = _controller([_entity(BARRACKS), _entity(FACTORY)])
	assert_eq(controller.producer_context_names().size(), 2)


func test_two_of_the_same_producer_are_one_context() -> void:
	var controller: RTSController = _controller([_entity(BARRACKS), _entity(BARRACKS)])
	assert_eq(controller.producer_context_names().size(), 1,
		"two barracks are one kind of producer, so one button speaks for both")


func test_a_selection_with_no_producer_draws_no_row() -> void:
	assert_eq(_controller([_entity(RECRUIT)]).producer_context_names(), [] as Array,
		"nothing to show, so nothing is drawn")


func test_a_unit_alongside_producers_is_not_a_context() -> void:
	var controller: RTSController = _controller(
		[_entity(BARRACKS), _entity(FACTORY), _entity(RECRUIT)])
	assert_eq(controller.producer_context_names().size(), 2, "only producers get a row")


# --- Radio semantics --------------------------------------------------------------

## Exactly one is always set. There is no "nothing chosen" state to fall into, which is why
## the settle runs from the available_commands setter beside the card's own.
func test_a_context_is_chosen_as_soon_as_the_row_appears() -> void:
	var controller: RTSController = _controller([_entity(BARRACKS), _entity(FACTORY)])
	assert_ne(controller.producer_context(), &"")
	assert_true(controller.producer_context_names().has(
		ProducerContextBinding.PREFIX + String(controller.producer_context())))


func test_the_chosen_context_is_greyed_and_unpressable() -> void:
	var controller: RTSController = _controller([_entity(BARRACKS), _entity(FACTORY)])
	var current: String = ProducerContextBinding.PREFIX + String(controller.producer_context())
	var state: CommandButtonState = CommandButtonState.of(
		current, controller.selection, null, false, current)
	assert_eq(state.blocker, CommandButtonState.Blocker.CURRENT)
	assert_eq(state.tint(), CommandButtonState.TINT_CURRENT)


func test_the_other_contexts_are_pressable() -> void:
	var controller: RTSController = _controller([_entity(BARRACKS), _entity(FACTORY)])
	var current: String = ProducerContextBinding.PREFIX + String(controller.producer_context())
	for name: String in controller.producer_context_names():
		if name == current:
			continue
		var state: CommandButtonState = CommandButtonState.of(
			name, controller.selection, null, false, current)
		assert_ne(state.blocker, CommandButtonState.Blocker.CURRENT, name)


func test_choosing_a_context_switches_to_it() -> void:
	var controller: RTSController = _controller([_entity(BARRACKS), _entity(FACTORY)])
	controller.choose_producer_context(&"cl_warFactory")
	assert_eq(controller.producer_context(), &"cl_warFactory")


## A context the new selection cannot fill is corrected, exactly as the card family is.
func test_a_context_the_selection_cannot_fill_is_corrected() -> void:
	var controller: RTSController = _controller([_entity(BARRACKS), _entity(FACTORY)])
	controller.choose_producer_context(&"cl_airField")
	controller.available_commands = CommandContextParser.commands_for_selection(
		controller.selection)
	assert_ne(controller.producer_context(), &"cl_airField",
		"no airfield is selected, so the card cannot be showing one")
