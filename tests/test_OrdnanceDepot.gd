extends GutTest

## The ordnance depot: free, never-recharging charges a commander casts with no caster piece.
## Rules: gdd/systems/combat/environmental-pieces.md §The ordnance depot.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_OrdnanceDepot.gd -gexit

const OWN: int = 1
const ABILITY: StringName = &"depot_test_strike"
const SANCTION_NAME: String = "Depot Test Strike"


## Counts what it is asked to do, standing in for an off-map payload.
class CountingEvent:
	extends AbstractEvent
	static var executions: int = 0
	## The anchor the last execution was handed, as an off-map event reads it.
	static var last_caster: Actor = null
	var commander_id: int = 0
	var caster: Actor = null

	func execute(_a_manager: ScenarioTriggerManager) -> void:
		executions += 1
		last_caster = caster


## Kept OUT of the tree (a scenario's _ready builds a match): the depot asks it only for its
## commanders and a piece by serial.
class StubScenario:
	extends Scenario
	var pieces: Dictionary = {}

	func piece_by_serial(a_serial: int) -> Entity:
		return pieces.get(a_serial)


## Reaches its trigger manager directly, so the manager can stand in the tree (an event is
## placed under it) while the scenario stays out of it.
class StubCommander:
	extends Commander
	var manager: ScenarioTriggerManager = null
	## What stands in for the command centre; null for a commander with none in play.
	var centre: Actor = null

	func scenario_event_manager() -> ScenarioTriggerManager:
		return manager

	func command_centre() -> Actor:
		return centre


var _commander: StubCommander
var _scenario: StubScenario

## An ordnance only a FOREIGN faction's grid authors (see test_a_foreign_faction_s_ordnance...).
const FOREIGN_ABILITY: StringName = &"depot_test_foreign_strike"


func before_each() -> void:
	CountingEvent.executions = 0
	CountingEvent.last_caster = null
	_scenario = StubScenario.new()
	autofree(_scenario)
	_commander = StubCommander.new()
	_commander.id = OWN
	add_child_autofree(_commander)
	_commander.manager = ScenarioTriggerManager.new()
	add_child_autofree(_commander.manager)
	_commander.scenario = _scenario
	_commander.sanction_grid = SanctionGrid.new(_commander, [_unlock(0)])
	_scenario.commanders.resize(OWN + 1)
	_scenario.commanders[OWN] = _commander


func after_each() -> void:
	OrdnanceDepot.faction_scenes = []
	OrdnanceDepot.reset_foreign_sanctions()


## A grid cell at `a_tier` granting ABILITY through a counting event.
func _unlock(a_tier: int, a_ability: StringName = ABILITY) -> SanctionUnlock:
	var sanction := Sanction.new()
	sanction.sanction_name = SANCTION_NAME
	sanction.ability_id = a_ability
	sanction.ability_level = a_tier + 1
	sanction.needs_vision = false
	var scene := PackedScene.new()
	var event := CountingEvent.new()
	scene.pack(event)
	event.free()
	sanction.event_scene = scene
	var unlock := SanctionUnlock.new()
	unlock.sanction = sanction
	unlock.tier = a_tier
	unlock.column = 0
	return unlock


func _depot() -> OrdnanceDepot:
	return _commander.ordnance_depot


func test_charges_are_granted_counted_and_spent() -> void:
	assert_false(_depot().has_charge(ABILITY), "empty to begin with")
	_depot().grant(ABILITY, 2)
	assert_eq(_depot().charges_of(ABILITY), 2)
	assert_eq(_depot().granted_abilities(), [ABILITY] as Array[StringName])
	assert_true(_depot().spend(ABILITY))
	assert_true(_depot().spend(ABILITY))
	assert_false(_depot().spend(ABILITY), "nothing left to spend")
	assert_eq(_depot().granted_abilities(), [] as Array[StringName], "an empty purse lists nothing")


func test_the_cell_with_nothing_unlocked_is_the_lowest_tier() -> void:
	var entry: SanctionGrid.Entry = _commander.sanction_grid.entry_for_ability(ABILITY)
	assert_eq(entry.tier(), 0)
	assert_false(entry.owned, "found without being unlocked")
	assert_null(_commander.sanction_grid.entry_for_ability(&"nothing_grants_this"))


func test_a_cast_fires_the_event_once_and_spends_one_charge() -> void:
	_depot().grant(ABILITY, 1)
	assert_true(_depot().cast(ABILITY, Vector3.ZERO))
	assert_eq(CountingEvent.executions, 1)
	assert_false(_depot().has_charge(ABILITY))


func test_a_cast_without_a_charge_does_nothing() -> void:
	assert_false(_depot().cast(ABILITY, Vector3.ZERO))
	assert_eq(CountingEvent.executions, 0)


func test_an_ordnance_the_grid_has_no_cell_for_cannot_be_cast() -> void:
	_depot().grant(&"nothing_grants_this", 1)
	assert_false(_depot().cast(&"nothing_grants_this", Vector3.ZERO))
	assert_true(_depot().has_charge(&"nothing_grants_this"), "the charge is kept")


func test_a_depot_order_through_the_dispatcher_casts() -> void:
	_depot().grant(ABILITY, 1)
	var order := PlayerOrder.new(
		PlayerOrder.Kind.CAST_FROM_DEPOT,
		OWN,
		{"ability": String(ABILITY), "position": [1.0, 0.0, 2.0], "target": 0, "payload": ""}
	)
	OrderDispatcher.apply(order, _scenario)
	assert_eq(CountingEvent.executions, 1)
	assert_false(_depot().has_charge(ABILITY))


## A faction scene whose grid holds `a_unlocks`, installed as the one the depot looks up.
func _install_foreign_faction(a_unlocks: Array) -> void:
	var faction := Faction.new()
	faction.sanction_unlocks.assign(a_unlocks)
	var scene := PackedScene.new()
	scene.pack(faction)
	faction.free()
	OrdnanceDepot.faction_scenes = [scene]
	OrdnanceDepot.reset_foreign_sanctions()


func test_the_lowest_non_passive_level_is_picked_per_ability() -> void:
	var passive: SanctionUnlock = _unlock(0, FOREIGN_ABILITY)
	passive.sanction.passive = true
	var lowest: Dictionary = OrdnanceDepot.lowest_sanctions_in(
		[_unlock(2), _unlock(1), passive, _unlock(3, FOREIGN_ABILITY), null]
	)
	assert_eq(lowest[ABILITY].ability_level, 2, "tier 1 beats tier 2")
	assert_eq(lowest[FOREIGN_ABILITY].ability_level, 4, "the passive cell is passed over")


func test_a_foreign_faction_s_ordnance_is_cast_through_its_lowest_level() -> void:
	_install_foreign_faction([_unlock(2, FOREIGN_ABILITY), _unlock(1, FOREIGN_ABILITY)])
	assert_null(_commander.sanction_grid.entry_for_ability(FOREIGN_ABILITY), "not on own grid")
	var sanction: Sanction = _depot().sanction_for(FOREIGN_ABILITY)
	assert_not_null(sanction, "found on the foreign grid")
	assert_eq(sanction.ability_level, 2)
	_depot().grant(FOREIGN_ABILITY, 1)
	assert_true(_depot().cast(FOREIGN_ABILITY, Vector3.ZERO))
	assert_eq(CountingEvent.executions, 1)
	assert_false(_depot().has_charge(FOREIGN_ABILITY))


func test_the_own_grid_s_cell_wins_over_a_foreign_one() -> void:
	_install_foreign_faction([_unlock(0)])
	assert_eq(
		_depot().sanction_for(ABILITY),
		_commander.sanction_grid.entry_for_ability(ABILITY).sanction,
		"the commander's own cell, not another faction's"
	)


func test_a_cast_is_anchored_on_the_command_centre() -> void:
	var centre: Actor = FakePieces.structure({})
	add_child_autofree(centre)
	_commander.centre = centre
	_depot().grant(ABILITY, 2)
	assert_true(_depot().cast(ABILITY, Vector3.ZERO))
	assert_eq(CountingEvent.last_caster, centre, "the centre is the caster an off-map event reads")
	_commander.centre = null
	assert_true(_depot().cast(ABILITY, Vector3.ZERO))
	assert_null(CountingEvent.last_caster, "no centre, no anchor")
