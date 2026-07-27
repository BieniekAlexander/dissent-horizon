extends GutTest

## The passive-ability row in the InfoSection: which cards appear for a selection, and which
## of them are greyed.
##
## A passive is never fired — no command, no charges, no cell on any command card — so before
## this row nothing on screen said a selected piece had one. Both rules here are static and
## read a selection plus a commander, so they run with no HUD in the tree.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd \
##     -gtest=res://tests/test_PassiveAbilityCards.gd -gexit

## A PASSIVE the shipped roster carries. Read off the catalog rather than written as a
## literal, so this file fails loudly if the roster stops having one at all — which would
## make every assertion below vacuously true.
var _passive_id: StringName = &""

## A passive that is DOMINION-UNLOCKED, which is a different thing and the greying tests need
## it specifically: `is_enabled` short-circuits to true for a FREE passive, so asking whether
## an unbought one is greyed is only a question about a passive something can buy.
##
## Two vars rather than one, because the first passive in catalog order is not necessarily
## dominion-unlocked and never was guaranteed to be — it just happened to be, until the
## roster gained a free passive that sorts earlier. That is exactly the kind of accident a
## fixture should not depend on.
var _dominion_passive_id: StringName = &""
var _commander: Commander


func before_all() -> void:
	for id: StringName in AbilityCatalog.ids():
		if not AbilityCatalog.is_passive(id):
			continue
		if _passive_id == &"":
			_passive_id = id
		if _dominion_passive_id == &"" and AbilityCatalog.is_dominion_unlocked(id):
			_dominion_passive_id = id


func before_each() -> void:
	_commander = Commander.new()
	_commander.id = 1
	_commander.dominion = 10000


func after_each() -> void:
	_commander.free()


func test_the_roster_still_has_a_passive_to_test_with() -> void:
	assert_ne(_passive_id, &"", "no ability is marked passive — the rest of this file is vacuous")
	assert_ne(_dominion_passive_id, &"",
		"no passive is dominion-unlocked — the greying tests below are vacuous")


## A grid holding one passive cell for `a_ability_id`, plus an ordinary cell so tier 1 opens.
func _grid_offering(a_ability_id: StringName) -> SanctionGrid:
	var passive := Sanction.new()
	passive.sanction_name = "Passive"
	passive.passive = true
	passive.ability_id = a_ability_id
	var passive_unlock := SanctionUnlock.new()
	passive_unlock.sanction = passive
	passive_unlock.tier = 0
	passive_unlock.column = 0
	var other := Sanction.new()
	other.sanction_name = "Other"
	var other_unlock := SanctionUnlock.new()
	other_unlock.sanction = other
	other_unlock.tier = 0
	other_unlock.column = 1
	var grid := SanctionGrid.new(_commander, [passive_unlock, other_unlock])
	_commander.sanction_grid = grid
	return grid


## A bare Entity owned by `a_commander` — no scene, because the row asks a selected node only
## two things: who owns it, and what its Abilities pool grants. Ownership is assigned directly
## rather than through initialize(), so no Map is needed (see test_Garrison._entity).
func _unit(a_commander: Commander) -> Entity:
	var unit := Entity.new()
	var ownership := Ownership.new()
	ownership.name = "Ownership"
	unit.add_child(ownership)
	add_child_autofree(unit)
	unit.ownership.commander = a_commander
	return unit


## A commander that is not the local one, for the enemy-selection case.
func _other_commander() -> Commander:
	var other := Commander.new()
	other.id = 2
	add_child_autofree(other)
	return other


#region Which cards appear
func test_no_commander_means_no_cards() -> void:
	assert_eq(PassiveAbilityRow.passives_in([], null), [] as Array[StringName],
		"the row is about THIS commander's standing benefits, and there is none")


func test_an_empty_selection_draws_nothing() -> void:
	_grid_offering(_passive_id)
	assert_eq(PassiveAbilityRow.passives_in([], _commander), [] as Array[StringName],
		"a commander-wide passive still needs one of the player's own pieces selected")


func test_a_faction_that_offers_it_draws_it_unbought() -> void:
	var grid: SanctionGrid = _grid_offering(_passive_id)
	assert_false(grid.entries[0].owned, "nothing has been unlocked")
	assert_eq(
		PassiveAbilityRow.passives_in([_unit(_commander)], _commander),
		[_passive_id] as Array[StringName],
		"drawing it unbought is how the player learns it exists")


func test_a_faction_with_no_route_to_it_draws_nothing() -> void:
	_grid_offering(&"not_a_real_ability")
	assert_eq(PassiveAbilityRow.passives_in([_unit(_commander)], _commander), [] as Array[StringName],
		"absent means 'not for you'; grey would say 'work toward it'")


func test_another_commanders_pieces_do_not_count() -> void:
	_grid_offering(_passive_id)
	assert_eq(
		PassiveAbilityRow.passives_in([_unit(_other_commander())], _commander),
		[] as Array[StringName],
		"an enemy's standing benefits are not the player's business")


func test_one_card_per_ability_however_many_units_carry_it() -> void:
	_grid_offering(_passive_id)
	var drawn: Array[StringName] = PassiveAbilityRow.passives_in(
		[_unit(_commander), _unit(_commander), _unit(_commander)], _commander)
	assert_eq(drawn.size(), 1, "the card is about the ability, not about the unit")
#endregion


#region Which cards are greyed
func test_an_unbought_dominion_passive_is_greyed() -> void:
	_grid_offering(_dominion_passive_id)
	assert_false(PassiveAbilityRow.is_enabled(_dominion_passive_id, _commander))


func test_buying_it_lights_it() -> void:
	var grid: SanctionGrid = _grid_offering(_dominion_passive_id)
	assert_true(grid.try_unlock(grid.entries[0]), "the cell is affordable and open")
	assert_true(PassiveAbilityRow.is_enabled(_dominion_passive_id, _commander),
		"an owned passive STANDS — see SanctionGrid.standing_sanctions")


func test_a_free_passive_is_always_lit() -> void:
	# Nothing unlocks it, so there is nothing to buy and nothing to grey.
	for id: StringName in AbilityCatalog.ids():
		if AbilityCatalog.is_passive(id) and not AbilityCatalog.is_dominion_unlocked(id):
			assert_true(PassiveAbilityRow.is_enabled(id, _commander))
			return
	pass_test("no free passive in the roster today; the branch is still the right default")


func test_no_commander_greys_a_dominion_passive() -> void:
	assert_false(PassiveAbilityRow.is_enabled(_dominion_passive_id, null),
		"nothing has bought it, because there is nobody to have bought it")
#endregion


#region The stand-in glyph
## TODO in PassiveAbilityRow: the letter is a placeholder for an icon. Pinned so the
## placeholder is at least derived from the ability rather than hand-written per card.
func test_the_letter_is_the_titles_first_letter_uppercased() -> void:
	assert_eq(PassiveAbilityRow.letter_for(_passive_id),
		AbilityCatalog.title_of(_passive_id).substr(0, 1).to_upper())


func test_an_unknown_ability_still_gets_a_glyph() -> void:
	# title_of falls back to the raw id, so this is really "never returns an empty string".
	assert_ne(PassiveAbilityRow.letter_for(&"not_a_real_ability"), "")
#endregion
