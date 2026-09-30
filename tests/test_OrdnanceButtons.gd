extends GutTest

## THE SANCTION IS THE PERMISSION, and a piece's ability pool is not.
##
## A caster grants its abilities the moment it is built, whether or not the commander ever spent
## dominion on any of them — the pool is authored on the PIECE. So "something can cast it" and
## "the commander may use it" are different facts, and reading the first as the second drew every
## unbought sanction lit. It did so twice, by two routes: with nothing selected (the commander's
## own casters were consulted, and finding one short-circuited the unlock check) and with the
## caster selected (its pool answered directly).
##
## Everything here is fake (tests/_fake_pieces.gd): one ability, one sanction level that unlocks
## it, one caster. Which ordnances the shipped factions offer, and which cell each sits in, is
## content and is not asserted — this file used to audit it, and broke on every honest edit.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_OrdnanceButtons.gd -gexit

const ABILITY: StringName = &"fake_strike"
const LEVEL_TITLE: String = "Fake Strike 1"


func before_each() -> void:
	FakePieces.install_ability(ABILITY, {"range": 30.0, "dominion": true, "grid": [0, 0],
		"levels": [{"title": LEVEL_TITLE}]})


func after_each() -> void:
	FakePieces.restore_abilities()


## A commander whose grid offers ONE sanction: the first level of the fake ability.
func _commander_offering_the_ability() -> Commander:
	var commander := Commander.new()
	commander.id = 1
	add_child_autofree(commander)
	var sanction := Sanction.new()
	sanction.sanction_name = LEVEL_TITLE
	sanction.ability_id = ABILITY
	sanction.ability_level = 1
	var unlock := SanctionUnlock.new()
	unlock.sanction = sanction
	unlock.tier = 0
	unlock.column = 0
	unlock.dominion_cost = 100
	commander.sanction_grid = SanctionGrid.new(commander, [unlock])
	return commander


## A structure that can cast the ability, owned by `a_commander`.
func _caster(a_commander: Commander) -> Commandable:
	var caster: Commandable = FakePieces.structure({"abilities": [{"grants": [ABILITY]}]})
	add_child_autofree(caster)
	caster.ownership.commander = a_commander
	assert_true((caster.get_node("Abilities") as Abilities).grants(ABILITY), "guards the fixture")
	return caster


## Route one: nothing selected, so the commander's own casters are consulted.
func test_owning_the_caster_does_not_unlock_a_sanction() -> void:
	var commander: Commander = _commander_offering_the_ability()
	_caster(commander)
	var state: CommandButtonState = CommandButtonState.of(
		Sanction.command_name_for(LEVEL_TITLE), [], commander, false)
	assert_eq(state.blocker, CommandButtonState.Blocker.LOCKED,
		"unbought, however many buildings could cast it")


## Route two: the caster is SELECTED, so its pool answers directly. The pool says the piece can
## cast, not that the commander may.
func test_selecting_the_caster_does_not_unlock_a_sanction_either() -> void:
	var commander: Commander = _commander_offering_the_ability()
	var caster: Commandable = _caster(commander)
	var state: CommandButtonState = CommandButtonState.of(
		Sanction.command_name_for(LEVEL_TITLE), [caster], commander, false)
	assert_eq(state.blocker, CommandButtonState.Blocker.LOCKED)


## And once it IS bought, the same selection reads as available.
func test_unlocking_it_lights_the_button() -> void:
	var commander: Commander = _commander_offering_the_ability()
	var caster: Commandable = _caster(commander)
	var grid: SanctionGrid = commander.sanction_grid
	commander.dominion = 99999
	assert_true(grid.try_unlock(grid.entries[0]), "bought")
	var state: CommandButtonState = CommandButtonState.of(
		grid.entries[0].sanction.command_name(), [caster], commander, false)
	assert_eq(state.blocker, CommandButtonState.Blocker.NONE)


## The card's filter asks the faction's own SANCTION GRID, not a faction tag: `faction_name` is
## flavour text ("Haustoria"), so keying on it matched nothing and put every faction's
## ordnances on every card.
func test_the_card_filter_does_not_key_on_flavour_text() -> void:
	var faction := autofree(Faction.new()) as Faction
	faction.faction_name = "Haustoria"
	assert_false(ControlBinding.Faction.has(faction.faction_name.to_upper()),
		"a faction's NAME is prose and matches no enum member")
