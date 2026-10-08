extends GutTest

## Row 0 of the PRODUCTION card: one radio button per producer TYPE in the selection, picking
## whose training the card is showing.
##
## The design decision these pin is that a context cell is a STATIC property of a piece
## (`ui.context_grid`) rather than packed left per selection. Packing would move a war
## factory's button from W to Q depending on what else was picked up, and a key that trains one
## thing in one selection and another in the next is what positional hotkeys exist to prevent.

## Fake producers, each registered as a tool with its own static row-0 cell; a unit that produces
## nothing.
const BARRACKS: Dictionary = {"id": &"fake_barracks", "structure": true, "production": true}
const FACTORY: Dictionary = {"id": &"fake_factory", "structure": true, "production": true}
const RECRUIT: Dictionary = {"speed": 2.0, "weapon": {"ground": 6.0}}


func before_each() -> void:
	FakePieces.register_tool(
		FakePieces.tool(
			&"fake_barracks", BARRACKS, [], ControlBinding.ControlContext.BUILD, [], Vector2i(1, 0)
		)
	)
	FakePieces.register_tool(
		FakePieces.tool(
			&"fake_factory", FACTORY, [], ControlBinding.ControlContext.BUILD, [], Vector2i(2, 0)
		)
	)
	FakePieces.register_tool(
		FakePieces.tool(
			&"fake_airfield",
			{"structure": true, "production": true},
			[],
			ControlBinding.ControlContext.BUILD,
			[],
			Vector2i(3, 0)
		)
	)


func after_each() -> void:
	FakePieces.restore_tools()


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


func _entity(a_options: Dictionary) -> Actor:
	var commander := Commander.new()
	commander.id = 1
	add_child_autofree(commander)
	var entity := FakePieces.make(a_options) as Actor
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
		assert_ne(
			piece.context_grid, Vector2i(-1, -1), "%s is a producer, so it needs a row-0 cell" % id
		)


## The context cell is a SECOND cell — `grid` is where the piece's own build button sits on a
## builder's menu, which is a different button in a different list.
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
	assert_eq(
		CommandButtonState.of(current, controller.selection, null, false, current).blocker,
		CommandButtonState.Blocker.CURRENT,
		"and it is the greyed, unpressable one"
	)


func test_two_producer_types_draw_the_row() -> void:
	var controller: RTSController = _controller([_entity(BARRACKS), _entity(FACTORY)])
	assert_eq(controller.producer_context_names().size(), 2)


func test_two_of_the_same_producer_are_one_context() -> void:
	var controller: RTSController = _controller([_entity(BARRACKS), _entity(BARRACKS)])
	assert_eq(
		controller.producer_context_names().size(),
		1,
		"two barracks are one kind of producer, so one button speaks for both"
	)


func test_a_selection_with_no_producer_draws_no_row() -> void:
	assert_eq(
		_controller([_entity(RECRUIT)]).producer_context_names(),
		[] as Array,
		"nothing to show, so nothing is drawn"
	)


func test_a_unit_alongside_producers_is_not_a_context() -> void:
	var controller: RTSController = _controller(
		[_entity(BARRACKS), _entity(FACTORY), _entity(RECRUIT)]
	)
	assert_eq(controller.producer_context_names().size(), 2, "only producers get a row")


# --- Radio semantics --------------------------------------------------------------


## Exactly one is always set. There is no "nothing chosen" state to fall into, which is why
## the settle runs from the available_commands setter beside the card's own.
func test_a_context_is_chosen_as_soon_as_the_row_appears() -> void:
	var controller: RTSController = _controller([_entity(BARRACKS), _entity(FACTORY)])
	assert_ne(controller.producer_context(), &"")
	assert_true(
		controller.producer_context_names().has(
			ProducerContextBinding.PREFIX + String(controller.producer_context())
		)
	)


func test_the_chosen_context_is_greyed_and_unpressable() -> void:
	var controller: RTSController = _controller([_entity(BARRACKS), _entity(FACTORY)])
	var current: String = ProducerContextBinding.PREFIX + String(controller.producer_context())
	var state: CommandButtonState = CommandButtonState.of(
		current, controller.selection, null, false, current
	)
	assert_eq(state.blocker, CommandButtonState.Blocker.CURRENT)
	assert_eq(state.tint(), CommandButtonState.TINT_CURRENT)


func test_the_other_contexts_are_pressable() -> void:
	var controller: RTSController = _controller([_entity(BARRACKS), _entity(FACTORY)])
	var current: String = ProducerContextBinding.PREFIX + String(controller.producer_context())
	for name: String in controller.producer_context_names():
		if name == current:
			continue
		var state: CommandButtonState = CommandButtonState.of(
			name, controller.selection, null, false, current
		)
		assert_ne(state.blocker, CommandButtonState.Blocker.CURRENT, name)


func test_choosing_a_context_switches_to_it() -> void:
	var controller: RTSController = _controller([_entity(BARRACKS), _entity(FACTORY)])
	controller.choose_producer_context(&"fake_factory")
	assert_eq(controller.producer_context(), &"fake_factory")


## A context the new selection cannot fill is corrected, exactly as the card family is.
func test_a_context_the_selection_cannot_fill_is_corrected() -> void:
	var controller: RTSController = _controller([_entity(BARRACKS), _entity(FACTORY)])
	controller.choose_producer_context(&"fake_airfield")
	controller.available_commands = CommandContextParser.commands_for_selection(
		controller.selection
	)
	assert_ne(
		controller.producer_context(),
		&"fake_airfield",
		"no airfield is selected, so the card cannot be showing one"
	)


## The cell's KEY does what clicking its button does. A grid key is positional — it names a cell
## and runs whatever that cell draws — so a context button is reached by its key as well as by
## the pointer, and the key must not drop it for not being an order.
func test_a_context_cells_hotkey_switches_to_it() -> void:
	# The row's bindings exist only for producers something trains, and are cached on first
	# use — so a trainee is registered and the cache rebuilt around it.
	FakePieces.register_tool(
		FakePieces.tool(
			&"fake_trainee",
			RECRUIT,
			[],
			ControlBinding.ControlContext.TRAIN,
			[&"fake_barracks", &"fake_factory"]
		)
	)
	ProducerContextBinding._bindings = []
	var trains: Dictionary = {"produces": [&"fake_trainee"]}
	var controller: RTSController = _controller(
		[_entity(BARRACKS.merged(trains)), _entity(FACTORY.merged(trains))]
	)
	controller.set_command_family(ControlBinding.CommandFamily.PRODUCTION)
	assert_eq(controller.command_family, ControlBinding.CommandFamily.PRODUCTION)
	controller.choose_producer_context(&"fake_barracks")
	var cell: Vector2i = Tool.for_id(&"fake_factory").context_grid
	controller._dispatch_command_hotkey([String(ControlBinding.cell_action(cell))])
	ProducerContextBinding._bindings = []
	assert_eq(controller.producer_context(), &"fake_factory")


# --- What the Details pane shows ----------------------------------------------------


## A controller whose local commander owns `a_entities`, which the info panel's production
## scope requires: another commander's queue is not the player's to read. The controller finds
## its commander as its parent when there is no scenario, so it is given one.
func _owned_controller(a_entities: Array) -> RTSController:
	var commander := autofree(Commander.new()) as Commander
	for entity: Actor in a_entities:
		entity.ownership.commander = commander
	var controller: RTSController = _controller(a_entities)
	commander.add_child(controller)
	return controller


## Trainable producers, so the PRODUCTION card can be entered and the context row is drawn.
func _register_trainee() -> Dictionary:
	FakePieces.register_tool(
		FakePieces.tool(
			&"fake_trainee",
			RECRUIT,
			[],
			ControlBinding.ControlContext.TRAIN,
			[&"fake_barracks", &"fake_factory"]
		)
	)
	ProducerContextBinding._bindings = []
	return {"produces": [&"fake_trainee"]}


func test_details_show_no_production_off_the_production_card() -> void:
	var trains: Dictionary = _register_trainee()
	# A unit beside the barracks, because a lone producer opens straight onto its PRODUCTION
	# card; a mixed selection rests on ACTIVE.
	var controller: RTSController = _owned_controller(
		[_entity(BARRACKS.merged(trains)), _entity(RECRUIT)]
	)
	ProducerContextBinding._bindings = []
	assert_eq(controller.command_family, ControlBinding.CommandFamily.ACTIVE)
	assert_eq(controller.production_detail_scope(), [])


func test_details_show_the_chosen_contexts_producers() -> void:
	var trains: Dictionary = _register_trainee()
	var barracks: Actor = _entity(BARRACKS.merged(trains))
	var other_barracks: Actor = _entity(BARRACKS.merged(trains))
	var factory: Actor = _entity(FACTORY.merged(trains))
	var controller: RTSController = _owned_controller([barracks, factory, other_barracks])
	controller.set_command_family(ControlBinding.CommandFamily.PRODUCTION)
	controller.choose_producer_context(&"fake_barracks")
	ProducerContextBinding._bindings = []
	assert_eq(controller.production_detail_scope(), [barracks, other_barracks])


func test_details_leave_out_another_commanders_producer() -> void:
	var trains: Dictionary = _register_trainee()
	var own: Actor = _entity(BARRACKS.merged(trains))
	var theirs: Actor = _entity(BARRACKS.merged(trains))
	var controller: RTSController = _owned_controller([own])
	controller.selection.append(theirs)
	controller.set_command_family(ControlBinding.CommandFamily.PRODUCTION)
	ProducerContextBinding._bindings = []
	assert_eq(controller.production_detail_scope(), [own])
