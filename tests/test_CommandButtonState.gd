extends GutTest

## ONE vocabulary for why a command-grid button is dark, across every kind of button.
##
## Before `CommandButtonState`, purchases had a five-way per-blocker idiom and abilities had
## on-or-greyed, so the same refusal looked different depending on which half of the grid it
## came from and only a purchase could say WHY. These tests pin the classification and the
## colours; the drawing is `VerboseTooltipButton.show_availability`, covered below.
##
## Every piece and tool is a fake (tests/_fake_pieces.gd).

## A gun carrying the bombard ability pool; a plain unit that cannot cast it.
const CANNON: Dictionary = {
	"structure": true,
	"dimensions": Vector2i(2, 2),
	"abilities": [{"grants": [&"bombard"], "cooldown_ticks": 300}]
}
const RECRUIT: Dictionary = FakePieces.PLAIN

const PLAYER: int = 1
## The Bombard's battery: the one ability that names its OWN grid command
## (`AbilityCatalog.command_of`), so it needs no sanction grid standing behind it. A
## sanction's command name is derived from its title instead and is covered by the routing
## test at the end.
const POOLED_ABILITY: StringName = &"bombard"

const HELD: bool = true
const NOT_HELD: bool = false

const _TRAINEE_COMMAND: String = "command_tool_fake_trainee"


func before_each() -> void:
	FakePieces.register_tool(
		FakePieces.tool(&"fake_trainee", FakePieces.PLAIN, [], ControlBinding.ControlContext.TRAIN)
	)
	FakePieces.install_ability(POOLED_ABILITY, {"command": "command_bombard", "range": 30.0})


func after_each() -> void:
	FakePieces.restore_tools()
	FakePieces.restore_abilities()


func _commander() -> Commander:
	var commander := Commander.new()
	commander.id = PLAYER
	commander.technology_mapping = {&"fake_trainee": FakePieces.tech(100)}
	add_child_autofree(commander)
	return commander


func _entity(a_options: Dictionary) -> Commandable:
	var entity: Commandable = FakePieces.make(a_options) as Commandable
	add_child_autofree(entity)
	entity.ownership.commander = _commander()
	return entity


func _state(
	a_command: String, a_selection: Array, a_commander: Commander, a_defers: bool
) -> CommandButtonState:
	return CommandButtonState.of(a_command, a_selection, a_commander, a_defers)


# --- Purchases -------------------------------------------------------------------


func test_an_affordable_unlocked_purchase_is_not_blocked() -> void:
	var commander: Commander = _commander()
	commander.energy = 100000
	var tool: Tool = Tool.for_name(_TRAINEE_COMMAND)
	assert_not_null(tool, "guards the fixture: the fake tool is registered")
	var state: CommandButtonState = _state(tool.command_name, [], commander, NOT_HELD)
	assert_eq(
		state.blocker,
		CommandButtonState.Blocker.NONE,
		"paid for and unrestricted by this bare commander's technology"
	)


func test_a_locked_piece_is_grey() -> void:
	var locked := CommandButtonState.new()
	locked.blocker = CommandButtonState.Blocker.LOCKED
	assert_eq(locked.tint(), CommandButtonState.TINT_LOCKED)


## The click decides the colour: without the modifier an unaffordable purchase is REFUSED, so it
## says "possible, but only if queued"; with the modifier the click queues it, so it looks like
## any button that works.
func test_an_unaffordable_purchase_is_amber_and_lit_under_the_modifier() -> void:
	var commander: Commander = _commander()
	commander.energy = 0
	var refused: CommandButtonState = _state(_TRAINEE_COMMAND, [], commander, NOT_HELD)
	assert_eq(refused.blocker, CommandButtonState.Blocker.UNAFFORDABLE)
	assert_true(refused.is_waitable)
	assert_false(refused.is_queueable, "clicking now is refused")
	assert_eq(refused.tint(), CommandButtonState.TINT_QUEUEABLE)
	var queued: CommandButtonState = _state(_TRAINEE_COMMAND, [], commander, HELD)
	assert_true(queued.is_queueable, "the same refusal, now queueable")
	assert_eq(queued.tint(), CommandButtonState.TINT_AVAILABLE)


func test_a_blocker_waiting_cannot_clear_keeps_its_own_colour_under_the_modifier() -> void:
	var locked := CommandButtonState.new()
	locked.blocker = CommandButtonState.Blocker.LOCKED
	assert_false(locked.is_waitable, "nothing on its way")
	assert_eq(locked.tint(), CommandButtonState.TINT_LOCKED)


func test_a_purchase_carries_no_charges() -> void:
	var state: CommandButtonState = _state(_TRAINEE_COMMAND, [], _commander(), NOT_HELD)
	assert_false(state.shows_charges(), "a price is not a pool")
	assert_false(state.shows_timer())


# --- Abilities -------------------------------------------------------------------


func test_a_loaded_ability_is_not_blocked() -> void:
	var cannon: Commandable = _entity(CANNON)
	var pool := cannon.get_node("Abilities") as Abilities
	assert_true(pool.grants(POOLED_ABILITY), "guards the fixture")
	var state: CommandButtonState = _state(
		AbilityCatalog.command_of(POOLED_ABILITY), [cannon], cannon.commander, NOT_HELD
	)
	assert_eq(state.blocker, CommandButtonState.Blocker.NONE)
	assert_eq(state.tint(), CommandButtonState.TINT_AVAILABLE)


func test_a_spent_pool_reads_recharging_with_a_countdown() -> void:
	var cannon: Commandable = _entity(CANNON)
	var pool := cannon.get_node("Abilities") as Abilities
	assert_true(pool.spend(POOLED_ABILITY), "guards the fixture: the charge was there")
	var state: CommandButtonState = _state(
		AbilityCatalog.command_of(POOLED_ABILITY), [cannon], cannon.commander, NOT_HELD
	)
	assert_eq(state.blocker, CommandButtonState.Blocker.RECHARGING)
	assert_eq(
		state.tint(),
		CommandButtonState.TINT_QUEUEABLE,
		"waitable: the click is refused, and the modifier would queue it"
	)
	assert_gt(state.recharge_ticks, 0, "it says how long")
	assert_true(state.shows_timer())


## The whole point of extending the amber to abilities: a spent charge and an unmet price are
## one idea at the call site (CommandMessage.defer_if_unaffordable), so they are one idea on
## the button too.
func test_a_recharging_ability_is_queueable_while_the_modifier_is_held() -> void:
	var cannon: Commandable = _entity(CANNON)
	(cannon.get_node("Abilities") as Abilities).spend(POOLED_ABILITY)
	var state: CommandButtonState = _state(
		AbilityCatalog.command_of(POOLED_ABILITY), [cannon], cannon.commander, HELD
	)
	assert_eq(state.blocker, CommandButtonState.Blocker.RECHARGING, "still the same reason")
	assert_true(state.is_queueable, "but clicking now queues it")
	assert_eq(state.tint(), CommandButtonState.TINT_AVAILABLE)


## Every, not any — matching selection_precondition's rule that a command is available as
## soon as anybody can act on it.
func test_one_loaded_caster_keeps_the_button_lit() -> void:
	var spent: Commandable = _entity(CANNON)
	var loaded: Commandable = _entity(CANNON)
	(spent.get_node("Abilities") as Abilities).spend(POOLED_ABILITY)
	var state: CommandButtonState = _state(
		AbilityCatalog.command_of(POOLED_ABILITY), [spent, loaded], loaded.commander, NOT_HELD
	)
	assert_eq(state.blocker, CommandButtonState.Blocker.NONE)


## A selection that cannot cast falls through to the COMMANDER's casters rather than reading
## as unavailable — which is what the ORDNANCE card needs, since its buttons stand whatever is
## selected. With no caster anywhere it is NO_CASTER; see that section below.
func test_a_selection_that_cannot_cast_falls_through_to_the_commander() -> void:
	var cannon: Commandable = _entity(CANNON)
	var recruit := FakePieces.unit(RECRUIT)
	add_child_autofree(recruit)
	recruit.ownership.commander = cannon.commander
	var state: CommandButtonState = _state(
		AbilityCatalog.command_of(POOLED_ABILITY), [recruit], cannon.commander, NOT_HELD
	)
	assert_eq(
		state.blocker,
		CommandButtonState.Blocker.NONE,
		"a Recruit cannot bombard, but the commander's gun can"
	)


# --- Charge pips -----------------------------------------------------------------


func test_a_single_charge_pool_draws_no_pips() -> void:
	var cannon: Commandable = _entity(CANNON)
	var state: CommandButtonState = _state(
		AbilityCatalog.command_of(POOLED_ABILITY), [cannon], cannon.commander, NOT_HELD
	)
	assert_eq(state.max_charges, 1, "guards the fixture")
	assert_false(state.shows_charges(), "'1/1' says nothing a lit button does not")


func test_a_multi_charge_pool_draws_its_pips() -> void:
	var cannon: Commandable = _entity(CANNON)
	var pool := cannon.get_node("Abilities") as Abilities
	pool.groups = [
		{
			"initial_charges": 2,
			"max_charges": 3,
			"cooldown_ticks": 600,
			"grants": [POOLED_ABILITY],
		}
	]
	pool._rebuild()
	var state: CommandButtonState = _state(
		AbilityCatalog.command_of(POOLED_ABILITY), [cannon], cannon.commander, NOT_HELD
	)
	assert_eq(state.charges, 2)
	assert_eq(state.max_charges, 3)
	assert_true(state.shows_charges())
	assert_eq(state.blocker, CommandButtonState.Blocker.NONE, "two left is not recharging")


# --- Units ------------------------------------------------------------------------


## Ticks are what Abilities counts in; seconds are what a player reads. The factor is READ
## from the engine rather than typed, so a change to the physics rate cannot silently make
## every timer on screen wrong.
func test_the_countdown_is_reported_in_seconds() -> void:
	var state := CommandButtonState.new()
	state.recharge_ticks = Engine.physics_ticks_per_second * 3
	assert_almost_eq(state.recharge_seconds(), 3.0, 0.001)


func test_no_recharge_is_no_timer() -> void:
	assert_false(CommandButtonState.new().shows_timer())
	assert_eq(CommandButtonState.new().recharge_seconds(), 0.0)


# --- What the button actually draws -----------------------------------------------
##
## GUT covers no layout — a label can size to zero or anchor outside its parent and every
## test still passes (CLAUDE.md §Seeing the HUD without a screen). What CAN be pinned is that
## the overlays exist, carry the right text, fill the button rather than sitting beside it,
## and never eat the click. The full-rect + alignment construction is chosen precisely so
## there is no arithmetic left to get wrong.


func _button_showing(a_state: CommandButtonState) -> VerboseTooltipButton:
	var button := VerboseTooltipButton.new()
	button.simple_tooltip = "a tooltip, so the empty-tooltip guard stays quiet"
	add_child_autofree(button)
	button.size = Vector2(64, 40)
	button.show_availability(a_state)
	return button


func _overlay_texts(a_button: VerboseTooltipButton) -> Array[String]:
	var found: Array[String] = []
	for child: Node in a_button.get_children():
		var label := child as Label
		if label != null:
			found.append(label.text)
	return found


func test_a_plain_button_draws_no_overlay_text() -> void:
	var button: VerboseTooltipButton = _button_showing(CommandButtonState.new())
	for text: String in _overlay_texts(button):
		assert_eq(text, "", "nothing to say, so nothing is written")


func test_a_multi_charge_button_writes_its_pips() -> void:
	var state := CommandButtonState.new()
	state.charges = 2
	state.max_charges = 3
	assert_true(_overlay_texts(_button_showing(state)).has("2/3"))


func test_a_recharging_button_writes_a_countdown() -> void:
	var state := CommandButtonState.new()
	state.blocker = CommandButtonState.Blocker.RECHARGING
	state.recharge_ticks = Engine.physics_ticks_per_second * 4
	assert_true(
		_overlay_texts(_button_showing(state)).has("4.0"),
		"one decimal under ten seconds, so a short cooldown does not read as stalled"
	)


func test_a_long_countdown_drops_the_decimal() -> void:
	var state := CommandButtonState.new()
	state.recharge_ticks = Engine.physics_ticks_per_second * 45
	assert_true(
		_overlay_texts(_button_showing(state)).has("45"),
		"hundredths on a minute-long cooldown are noise"
	)


func test_the_button_takes_its_tint_from_the_state() -> void:
	var state := CommandButtonState.new()
	state.blocker = CommandButtonState.Blocker.LOCKED
	assert_eq(_button_showing(state).modulate, CommandButtonState.TINT_LOCKED)


func test_the_overlays_fill_the_button_and_never_take_the_click() -> void:
	var state := CommandButtonState.new()
	state.charges = 1
	state.max_charges = 2
	state.recharge_ticks = 30
	var button: VerboseTooltipButton = _button_showing(state)
	var labels: int = 0
	for child: Node in button.get_children():
		var label := child as Label
		if label == null:
			continue
		labels += 1
		assert_eq(
			label.mouse_filter,
			Control.MOUSE_FILTER_IGNORE,
			"an overlay that took the click would kill the button under it"
		)
		assert_eq(label.anchor_right, 1.0, "fills the button horizontally")
		assert_eq(label.anchor_bottom, 1.0, "and vertically — no corner box to mis-size")
	assert_eq(labels, 2, "both overlays exist once they are asked for")


func test_the_overlays_are_built_once_and_reused() -> void:
	var state := CommandButtonState.new()
	state.charges = 1
	state.max_charges = 2
	var button: VerboseTooltipButton = _button_showing(state)
	state.charges = 2
	button.show_availability(state)
	button.show_availability(state)
	assert_eq(_overlay_texts(button).size(), 2, "a per-frame repaint must not accrete nodes")
	assert_true(_overlay_texts(button).has("2/2"), "and it does update")


# --- Nothing to cast it with ------------------------------------------------------
##
## Only the ORDNANCE card can raise these: it is the one card that draws a button whether or
## not anything is selected, so "you own nothing that can do this" and "you never bought this"
## become answerable questions rather than buttons that are simply absent.


func test_no_caster_and_locked_are_told_apart() -> void:
	# Different remedies, so different colours: LOCKED wants dominion, NO_CASTER wants a piece.
	assert_ne(CommandButtonState.TINT_NO_CASTER, CommandButtonState.TINT_LOCKED)
	var no_caster := CommandButtonState.new()
	no_caster.blocker = CommandButtonState.Blocker.NO_CASTER
	assert_eq(no_caster.tint(), CommandButtonState.TINT_NO_CASTER)


## A free ability — the Bombard's battery, which no dominion unlocks — with no gun in play.
## The remedy is building one, not buying anything.
func test_an_unlocked_ability_with_nothing_to_cast_it_reads_no_caster() -> void:
	var commander: Commander = _commander()
	var state: CommandButtonState = _state(
		AbilityCatalog.command_of(POOLED_ABILITY), [], commander, NOT_HELD
	)
	assert_eq(
		state.blocker, CommandButtonState.Blocker.NO_CASTER, "the battery is yours; you have no gun"
	)


## The button speaks for the commander's casters when none is SELECTED — which is the state
## the ORDNANCE card is normally read in.
func test_an_unselected_caster_still_lights_the_button() -> void:
	var cannon: Commandable = _entity(CANNON)
	var state: CommandButtonState = _state(
		AbilityCatalog.command_of(POOLED_ABILITY), [], cannon.commander, NOT_HELD
	)
	assert_eq(
		state.blocker,
		CommandButtonState.Blocker.NONE,
		"you own a gun, so the button is live even with nothing selected"
	)


func test_an_unselected_caster_reports_its_cooldown() -> void:
	var cannon: Commandable = _entity(CANNON)
	(cannon.get_node("Abilities") as Abilities).spend(POOLED_ABILITY)
	var state: CommandButtonState = _state(
		AbilityCatalog.command_of(POOLED_ABILITY), [], cannon.commander, NOT_HELD
	)
	assert_eq(state.blocker, CommandButtonState.Blocker.RECHARGING)
	assert_gt(state.recharge_ticks, 0)


# --- The countdown belongs to the pool, not to being blocked ----------------------
##
## Charges and the time to the next one are drawn on the ABILITY'S OWN BUTTON. They were
## briefly lines in the info panel's summary instead, which makes a player look away from the
## button to find out about the button.


func test_a_partly_filled_pool_still_counts_down() -> void:
	var cannon: Commandable = _entity(CANNON)
	var pool := cannon.get_node("Abilities") as Abilities
	pool.groups = [
		{
			"initial_charges": 1,
			"max_charges": 3,
			"cooldown_ticks": 600,
			"grants": [POOLED_ABILITY],
		}
	]
	pool._rebuild()
	var state: CommandButtonState = _state(
		AbilityCatalog.command_of(POOLED_ABILITY), [cannon], cannon.commander, NOT_HELD
	)
	assert_eq(state.blocker, CommandButtonState.Blocker.NONE, "one charge left, so pressable")
	assert_true(state.shows_charges(), "and it says 1/3")
	assert_true(state.shows_timer(), "'when is the next charge' is asked of a button you CAN press")


func test_a_full_pool_counts_down_to_nothing() -> void:
	var cannon: Commandable = _entity(CANNON)
	var state: CommandButtonState = _state(
		AbilityCatalog.command_of(POOLED_ABILITY), [cannon], cannon.commander, NOT_HELD
	)
	assert_eq(state.recharge_ticks, 0, "nothing is owed at capacity")
	assert_false(state.shows_timer())
