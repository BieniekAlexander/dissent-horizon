extends GutTest

## The ORDNANCE card's buttons, built from the ability catalog rather than authored in code.
##
## Before this the card existed and was empty: a sanction's command had no `ControlBinding`,
## so backtick reached a titled blank page. `AbilityBinding` closes that, and these tests pin
## the three things that would silently break it — a missing cell, a command name that does
## not match the one the sanction actually fires, and two ordnances stacked in one cell where
## the player can only ever see one of them.

## Every ordnance the game has authored, by faction. Named here so a piece added without a
## cell fails LOUDLY rather than just never appearing on the card.
const COLONIAL: Array[StringName] = [&"bombard", &"promotion", &"scan", &"freeze", &"drop",
	&"beacon", &"gunship", &"blizzard"]
const ANARCHIST: Array[StringName] = [&"dignify", &"informant", &"ambush", &"mortar",
	&"overcharge", &"global_emp"]


func _ordnance_bindings() -> Array:
	return CommandGrid.bindings().filter(func(b: ControlBinding) -> bool:
		return b.family == ControlBinding.CommandFamily.ORDNANCE)


func test_every_authored_ordnance_has_a_cell() -> void:
	for id: StringName in COLONIAL + ANARCHIST:
		assert_true(AbilityCatalog.has(id), "%s is in the catalog" % id)
		assert_true(AbilityCatalog.has_hud_button(id), "%s is an ordnance" % id)
		assert_ne(AbilityCatalog.grid_of(id), Vector2i(-1, -1),
			"%s authors a cell, so it is drawn" % id)


## A LOCAL ability draws no ordnance button, so it needs no cell — and a passive is never a
## button at all.
func test_a_passive_authors_no_cell() -> void:
	assert_true(AbilityCatalog.is_passive(&"scavenge"))
	assert_eq(AbilityCatalog.grid_of(&"scavenge"), Vector2i(-1, -1))


func test_every_ordnance_binding_is_on_the_ordnance_card() -> void:
	var bindings: Array = _ordnance_bindings()
	assert_gt(bindings.size(), 0, "the card has buttons at all")
	for binding: ControlBinding in bindings:
		assert_true(binding is AbilityBinding)
		assert_true(ControlBinding.position_in_bounds(binding.grid_position),
			"%s is inside the grid" % binding.command_name)


## The load-bearing one. A dominion-unlocked ability is armed as its LEVEL's own command, and
## the binding derives that name from the level title exactly as `Sanction.command_name` does.
## Two derivations of one name is how a button and the command it fires come to disagree.
func test_a_levelled_ordnance_binds_one_command_per_level() -> void:
	var commands: Array[String] = AbilityCatalog.commands_of(&"scan")
	assert_eq(commands.size(), 3, "Scan 1, 2 and 3 are three commands")
	for title: String in ["Scan 1", "Scan 2", "Scan 3"]:
		assert_true(commands.has(Sanction.command_name_for(title)), title)


func test_the_binding_name_matches_what_the_sanction_actually_fires() -> void:
	var sanction := Sanction.new()
	sanction.sanction_name = "Scan 2"
	assert_true(AbilityCatalog.commands_of(&"scan").has(sanction.command_name()),
		"the grid draws the button the sanction's own command_name would arm")


## An ability with its own command (the Bombard's battery, which no dominion unlocks) binds
## that one name and nothing else.
func test_a_free_ordnance_binds_its_own_command() -> void:
	assert_eq(AbilityCatalog.commands_of(&"bombard"), ["command_bombard"] as Array[String])


## Bombard used to be a HAND-WRITTEN verb at (2, 0) on the ACTIVE card as well as an ability.
## It is still on both cards — deliberately, see below — but both bindings are now GENERATED
## from its doc. Two sources for one command is what would let a cell move on one card and not
## the other.
func test_bombard_is_generated_and_not_hand_written() -> void:
	var seen: Array = CommandGrid.bindings().filter(func(b: ControlBinding) -> bool:
		return b.command_name == "command_bombard")
	assert_eq(seen.size(), 2, "one binding per card")
	for binding: ControlBinding in seen:
		assert_true(binding is AbilityBinding, "generated from the ability doc, not authored")


## Rows are POWER TIERS: minor, mid, major. Global EMP is the Anarchists' deepest unlock and
## the example the idiom was stated with.
func test_the_deepest_sanction_sits_on_the_major_row() -> void:
	assert_eq(AbilityCatalog.grid_of(&"global_emp").y, 2)
	assert_eq(AbilityCatalog.grid_of(&"blizzard").y, 2, "and the Colonial one")


func test_a_starting_sanction_sits_on_the_minor_row() -> void:
	for id: StringName in [&"dignify", &"promotion", &"bombard"]:
		assert_eq(AbilityCatalog.grid_of(id).y, 0, id)


## Two ordnances may share a cell only when no commander could field both — which for
## ordnances means different factions. This is the same review every other binding gets; it is
## asserted here because the cells were authored by hand.
func test_no_two_ordnances_of_one_faction_share_a_cell() -> void:
	var collisions: Array = ControlBinding.grid_collisions(_ordnance_bindings())
	var cross_level: Array = collisions.filter(func(c: String) -> bool:
		# Levels of ONE ability share a cell by design — supersession keeps one live.
		var parts: PackedStringArray = c.split(" + ")
		return not _same_ability(parts[0].strip_edges(), parts[1].split(" @")[0].strip_edges()))
	assert_eq(cross_level, [] as Array,
		"two ordnances one commander could field are never stacked in one cell")


func _same_ability(a_first: String, a_second: String) -> bool:
	for binding: ControlBinding in _ordnance_bindings():
		if binding.command_name != a_first:
			continue
		for other: ControlBinding in _ordnance_bindings():
			if other.command_name == a_second:
				return (binding as AbilityBinding).ability_id \
					== (other as AbilityBinding).ability_id
	return false


# --- An ability on two cards ------------------------------------------------------
##
## The Bombard is both an ORDER you give a selected gun and a strike the commander calls in
## without selecting anything, so it is drawn on both cards. That makes it the first command
## with more than one binding, which is why button visibility is decided per BINDING (each
## button carries its own family) rather than per command name.

func test_the_bombard_is_drawn_on_both_cards() -> void:
	var families: int = CommandGrid.families_for("command_bombard")
	assert_ne(families & ControlBinding.CommandFamily.ORDNANCE, 0, "on the commander's card")
	assert_ne(families & ControlBinding.CommandFamily.ACTIVE, 0, "and on the gun's own")


func test_its_two_cards_use_different_cells() -> void:
	# A cell free on one card is spoken for on the other — (0, 0) on ACTIVE is Radiate. So the
	# two are separate bindings with separate cells, not one binding on two cards.
	var cells: Dictionary = {}
	for binding: ControlBinding in CommandGrid.bindings():
		if binding.command_name == "command_bombard":
			cells[binding.family] = binding.grid_position
	assert_eq(cells.size(), 2, "one binding per card")
	assert_ne(cells[ControlBinding.CommandFamily.ACTIVE],
		cells[ControlBinding.CommandFamily.ORDNANCE])


func test_an_ordinary_ordnance_claims_only_the_commander_card() -> void:
	assert_eq(AbilityCatalog.active_grid_of(&"scan"), Vector2i(-1, -1))
	assert_eq(CommandGrid.families_for("command_sanction_scan_1"),
		ControlBinding.CommandFamily.ORDNANCE)


## The regression the per-binding visibility rule prevents: looking a button's card up by
## COMMAND NAME returns whichever binding sorts first, so one of the two cards would draw the
## wrong thing — Bombard would appear at ACTIVE's (0, 0), on top of Radiate.
func test_a_cell_draws_only_bindings_of_the_card_on_show() -> void:
	var active_cells: Array[Vector2i] = []
	var ordnance_cells: Array[Vector2i] = []
	for binding: ControlBinding in CommandGrid.bindings():
		if binding.command_name != "command_bombard":
			continue
		if binding.family == ControlBinding.CommandFamily.ACTIVE:
			active_cells.append(binding.grid_position)
		else:
			ordnance_cells.append(binding.grid_position)
	assert_eq(active_cells, [Vector2i(2, 0)] as Array[Vector2i])
	assert_eq(ordnance_cells, [Vector2i(0, 0)] as Array[Vector2i])


# --- The commander's card shows everything ----------------------------------------
##
## The one card that draws a button for something the player cannot use yet. Everywhere else a
## button appears only when the selection offers its command — right for an ORDER, wrong here:
## the commander's card answers "what can I call in, and what would it take", and a locked
## ordnance is part of that answer.

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
	return controller


## Every ordnance the faction OFFERS gets a button, unlocked or not.
func test_every_offered_ability_gets_a_button_with_nothing_selected() -> void:
	var controller: RTSController = _colonial_controller()
	var names: Array = controller.ordnance_card_names()
	assert_gt(names.size(), 0, "the card is not empty just because nothing is selected")
	var seen: Array[StringName] = []
	for name: String in names:
		seen.append(controller.ordnance_ability_for(name))
	for id: StringName in COLONIAL:
		assert_true(seen.has(id), "%s has a button" % id)


## One button per ABILITY, not per level: a levelled sanction's three bindings share a cell and
## only the level the commander owns is drawn — falling back to the first, so a locked family
## still has a face.
func test_a_levelled_sanction_draws_one_button_not_three() -> void:
	var controller: RTSController = _colonial_controller()
	var names: Array = controller.ordnance_card_names()
	var scans: int = 0
	for name: String in names:
		if name.begins_with(Sanction.command_name_for("Scan").trim_suffix("scan")):
			pass
		if controller.ordnance_ability_for(name) == &"scan":
			scans += 1
	assert_eq(scans, 1, "Scan 1, 2 and 3 are one button")


func test_an_ordnance_command_resolves_back_to_its_ability() -> void:
	var controller: RTSController = _controller([])
	assert_eq(controller.ordnance_ability_for("command_bombard"), &"bombard")
	assert_eq(controller.ordnance_ability_for("command_attack_move"), &"",
		"a verb is not an ordnance")


## Bombard is drawn on both cards. Arming it from the commander's card must not throw the
## player onto the other one — `binding_for` returns whichever binding sorts first.
func test_arming_from_the_commander_card_stays_on_it() -> void:
	var controller: RTSController = _controller([])
	controller.set_command_family(ControlBinding.CommandFamily.ORDNANCE)
	controller._show_card_for_command("command_bombard")
	assert_eq(controller.command_family, ControlBinding.CommandFamily.ORDNANCE)


# --- The three the shipped card got wrong -----------------------------------------

## A controller whose parent is a Colonial commander, with NEITHER in the scene tree: the
## controller reads its commander through `get_parent()`, and entering a tree would run its
## `_ready`, which wants the whole HUD rig.
##
## The SANCTION GRID is the real one, built from the shipped Colonial faction — it is what
## decides which ordnances are on the card at all, so a stub would test nothing.
func _colonial_controller() -> RTSController:
	var faction: Faction = (load("res://scenes/factions/colonial.tscn") as PackedScene) \
		.instantiate() as Faction
	add_child_autofree(faction)
	var commander := autofree(Commander.new()) as Commander
	commander.id = 1
	commander.faction = faction
	commander.sanction_grid = SanctionGrid.new(commander, faction.sanction_unlocks)
	var controller := autofree(RTSController.new()) as RTSController
	# The empty CommandsView the repaint addresses with `$`. Required rather than optional —
	# set_command_family redraws, and a fixture without it is testing against a node the game
	# always has.
	var section := Control.new()
	section.name = "CommandsSection"
	var border := Control.new()
	border.name = "CommandsBorder"
	var view := Control.new()
	view.name = "CommandsView"
	border.add_child(view)
	section.add_child(border)
	controller.add_child(section)
	commander.add_child(controller)
	controller._sanction_grid = commander.sanction_grid
	return controller


## The commander's card is not selection-owned, so the empty-selection guard must not eat it —
## and "nothing selected" is the state it is normally read in.
func test_the_card_is_populated_with_nothing_selected() -> void:
	var controller: RTSController = _colonial_controller()
	controller.set_command_family(ControlBinding.CommandFamily.ORDNANCE)
	assert_true(controller.selection.is_empty(), "guards the fixture")
	assert_gt(controller._visible_command_names().size(), 0,
		"the card the player opened with nothing selected has buttons on it")


## Another faction's ordnances are not LOCKED, they are not on offer — drawing them dark would
## say the player could work toward them.
##
## Asked of the faction's own SANCTION GRID, not of a faction tag: `Faction.faction_name` is
## flavour text ("Haustoria", not "colonial"), so keying on it matched nothing and put every
## faction's ordnances on every card.
func test_a_colonial_commander_sees_no_anarchist_ordnances() -> void:
	var controller: RTSController = _colonial_controller()
	var seen: Array[StringName] = []
	for name: String in controller.ordnance_card_names():
		seen.append(controller.ordnance_ability_for(name))
	for id: StringName in COLONIAL:
		assert_true(seen.has(id), "%s is Colonial, so it is on the card" % id)
	for id: StringName in ANARCHIST:
		assert_false(seen.has(id), "%s is Anarchist, so it is not" % id)


## The tag exists for the collision review and is NOT the instrument here. Pinned so nobody
## reaches for it again.
func test_the_card_filter_does_not_key_on_flavour_text() -> void:
	var faction := autofree(Faction.new()) as Faction
	faction.faction_name = "Haustoria"
	assert_false(ControlBinding.Faction.has(faction.faction_name.to_upper()),
		"a faction's NAME is prose and matches no enum member")


## THE SANCTION IS THE PERMISSION, and a piece's ability pool is not.
##
## A Citadel grants Scan, Freeze, Beacon and Promotion the moment it is built, whether or not
## the commander ever spent dominion on any of them — the pool is authored on the PIECE. So
## "something can cast it" and "the commander may use it" are different facts, and reading the
## first as the second drew every unbought sanction lit. It did so twice, by two different
## routes, which is why both are pinned here.
func _citadel_of(a_controller: RTSController) -> Commandable:
	var citadel := (load("res://scenes/entities/structures/cl/cl_commandCenter.tscn") \
		as PackedScene).instantiate() as Commandable
	add_child_autofree(citadel)
	citadel.ownership.commander = a_controller._commander()
	assert_true((citadel.get_node("Abilities") as Abilities).grants(&"scan"),
		"guards the fixture: the Citadel casts Scan")
	return citadel


## Route one: nothing selected, so the commander's own casters were consulted — and finding
## one short-circuited the unlock check.
func test_owning_the_caster_does_not_unlock_a_sanction() -> void:
	var controller: RTSController = _colonial_controller()
	_citadel_of(controller)
	var state: CommandButtonState = CommandButtonState.of(
		Sanction.command_name_for("Scan 1"), [], controller._commander(), false)
	assert_eq(state.blocker, CommandButtonState.Blocker.LOCKED,
		"unbought, however many buildings could cast it")


## Route two: the caster is SELECTED, so its pool answered directly and the unlock check was
## skipped as already-answered. It was not answered — the pool says the piece can cast, not
## that the commander may.
func test_selecting_the_caster_does_not_unlock_a_sanction_either() -> void:
	var controller: RTSController = _colonial_controller()
	var citadel: Commandable = _citadel_of(controller)
	var state: CommandButtonState = CommandButtonState.of(
		Sanction.command_name_for("Scan 1"), [citadel], controller._commander(), false)
	assert_eq(state.blocker, CommandButtonState.Blocker.LOCKED,
		"selecting the building that would cast it is not buying it")
	assert_eq(state.tint(), CommandButtonState.TINT_LOCKED)


## And once it IS bought, the same selection reads as available.
func test_unlocking_it_lights_the_button() -> void:
	var controller: RTSController = _colonial_controller()
	var citadel: Commandable = _citadel_of(controller)
	var grid: SanctionGrid = controller._sanction_grid
	var scan: SanctionGrid.Entry = null
	for entry: SanctionGrid.Entry in grid.entries:
		if entry.sanction != null and entry.sanction.ability_id == &"scan" \
				and entry.sanction.ability_level == 1:
			scan = entry
			break
	assert_not_null(scan, "guards the fixture: the Colonial grid has a Scan 1 cell")
	controller._commander().dominion = 99999
	assert_true(grid.try_unlock(scan), "bought")
	var state: CommandButtonState = CommandButtonState.of(
		scan.sanction.command_name(), [citadel], controller._commander(), false)
	assert_eq(state.blocker, CommandButtonState.Blocker.NONE)


## A locked sanction has to resolve to its ability, or it cannot be told apart from a plain
## verb — which is how it came to be drawn lit while it was still unbought.
func test_a_locked_ordnance_resolves_to_its_ability_and_greys() -> void:
	var locked: String = Sanction.command_name_for("Scan 1")
	assert_eq(AbilityBinding.ability_for_command(locked), &"scan",
		"a command with no unlock behind it still names its ability")
	var commander := Commander.new()
	commander.id = 1
	add_child_autofree(commander)
	var state: CommandButtonState = CommandButtonState.of(locked, [], commander, false)
	assert_eq(state.blocker, CommandButtonState.Blocker.LOCKED,
		"never bought, so the remedy is dominion")
	assert_eq(state.tint(), CommandButtonState.TINT_LOCKED)


## The bar's own button carried the ABILITY's copy, which is empty for every levelled
## sanction — so it reached the player blank and VerboseTooltipButton reported it as a bug.
func test_a_levelled_ability_has_button_copy_to_show() -> void:
	for id: StringName in [&"scan", &"drop", &"ambush"]:
		var buttons: Array[Dictionary] = AbilityCatalog.buttons_of(id)
		assert_gt(buttons.size(), 0, "%s has levels" % id)
		assert_ne(str(buttons[0]["description"]), "",
			"%s's first level has words for its button" % id)
