extends GutTest

## THE PRODUCER RUNG (BotEconomy._production_structure_to_build): which production structure to
## add, priced by the one purchase valuation its units are chosen by (Bot.producer_values);
## a producer ordered but not yet placed counts as owned; a producer worth nothing — one that
## trains nothing armed, the command centre — is never bought here. The holes these pin were
## found 2026-10-09 in the learned-vs-demand ledger (gdd/tasks.md T-105).
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_BotProducerRung.gd -gexit

const CENTRE := &"centre"
const BARRACKS := &"barracks"
const FACTORY := &"factory"
const RECRUIT := &"recruit"
const TANK := &"tank"
const BUILDER := &"builder"


## A bot whose producers, their producibles and the unit values are tables the test writes.
class FakeBot:
	extends Bot
	var owned: Dictionary = {}  # structure type -> count
	var values: Dictionary = {}  # unit type -> demand-map value
	var producibles: Dictionary = {CENTRE: [BUILDER], BARRACKS: [RECRUIT], FACTORY: [TANK]}
	var buildable: Array = [CENTRE, BARRACKS, FACTORY]
	var locked: Array = []  # unit types the bot lacks the tech for

	func can_afford(_a_type: StringName) -> bool:
		return true

	func buildable_production_structure_types() -> Array:
		return buildable

	func get_structures_of_type(a_type: StringName) -> Array:
		var out: Array = []
		for i: int in int(owned.get(a_type, 0)):
			out.append(null)
		return out

	func producible_types_of(a_structure_type: StringName) -> Array:
		return producibles.get(a_structure_type, [])

	func enemy_demand_map() -> Dictionary:
		return {&"enemy": {"demand": 1.0, "rep": null}}

	func unit_composition_value(a_unit_type, _a_demand: Dictionary) -> float:
		return float(values.get(a_unit_type, 0.0))

	func unit_can_attack(a_type) -> bool:
		return a_type != BUILDER

	func has_tech_for(a_type) -> bool:
		return not locked.has(a_type)

	func own_armed_composition() -> Dictionary:
		return {}

	func believed_enemy_composition_clocked() -> Dictionary:
		return {&"raider": 2}


## The economy with its under-way list under the test's control.
class StubEconomy:
	extends BotEconomy
	var under_way: Array[StringName] = []

	func _types_under_way() -> Array[StringName]:
		return under_way

	func can_afford_above_reserve(_a_type) -> bool:
		return true


var _bot: FakeBot
var _economy: StubEconomy


func before_each() -> void:
	_bot = FakeBot.new()
	add_child_autofree(_bot)
	_bot.technology_mapping[RECRUIT] = TechnologySpec.new(100, 0, 0, 10)
	_bot.technology_mapping[TANK] = TechnologySpec.new(500, 0, 0, 30)
	_bot.technology_mapping[BARRACKS] = TechnologySpec.new(300, 0, 0, 30)
	_bot.technology_mapping[FACTORY] = TechnologySpec.new(1200, 0, 0, 30)
	_bot.technology_mapping[CENTRE] = TechnologySpec.new(1500, 0, 0, 30)
	_bot.values = {RECRUIT: 3.0, TANK: 2.0}
	_economy = StubEconomy.new(_bot, BotActuator.new(null), null)


func test_a_producer_of_nothing_armed_is_never_bought_even_as_the_lone_candidate() -> void:
	# The opening: the command centre is the only producer the bot may build, and it is
	# "unowned" because its own is still a pending drop.
	_bot.buildable = [CENTRE]
	assert_null(_economy._production_structure_to_build())


func test_an_ordered_producer_counts_as_owned() -> void:
	_bot.owned = {CENTRE: 1}
	_economy.under_way = [BARRACKS]
	# The barracks is on its way: the factory is the one producer not yet owned.
	assert_eq(_economy._production_structure_to_build(), FACTORY)
	_economy.under_way = [BARRACKS, FACTORY]
	# Nothing unowned: back to the whole affordable pool by value, where the demand map's 3.0
	# for the recruit beats the tank's 2.0 — a second barracks.
	assert_eq(_economy._production_structure_to_build(), BARRACKS)


func test_an_ordered_producer_counts_toward_the_cap() -> void:
	_bot.owned = {CENTRE: 1, BARRACKS: 1}
	_economy.production_structure_cap = 2
	_economy.under_way = [FACTORY]
	assert_null(_economy._production_structure_to_build(), "one owned and one ordered: capped")


func test_producers_are_priced_by_the_valuation_their_units_are_chosen_by() -> void:
	_bot.owned = {CENTRE: 1, BARRACKS: 1, FACTORY: 1}
	# The demand map prefers the recruit (3.0 to 2.0)...
	assert_eq(_economy._production_structure_to_build(), BARRACKS)
	# ...and the learned model, per energy, the tank: the rung follows the same switch the
	# unit choice does, so the producer it adds is the one the picker would fill best.
	_bot.combat_model = (
		CombatModel
		. from_dict(
			{
				"intercept": 0.0,
				"cap": 8,
				"types": [RECRUIT, TANK, &"raider"],
				"main":
				{
					"own:recruit": [0.0, 0.05, 0.1, 0.15, 0.2, 0.25, 0.3, 0.35, 0.4],
					"own:tank": [0.0, 0.8, 1.6, 2.4, 3.2, 4.0, 4.8, 5.6, 6.4],
					"enemy:raider": [0.0, -0.3, -0.6, -0.9, -1.2, -1.5, -1.8, -2.1, -2.4],
				},
				"pairs": [],
			}
		)
	)
	_bot.should_use_learned_production = true
	assert_eq(_economy._production_structure_to_build(), FACTORY)
	var values: Dictionary = _bot.producer_values([BARRACKS, FACTORY, CENTRE])
	assert_eq(float(values[CENTRE]), 0.0, "a builder is not a fighter")
	assert_gt(float(values[FACTORY]), float(values[BARRACKS]))


func test_a_locked_unit_does_not_price_its_producer() -> void:
	_bot.owned = {CENTRE: 1, BARRACKS: 1, FACTORY: 1}
	_bot.values = {RECRUIT: 1.0, TANK: 9.0}
	_bot.locked = [TANK]
	assert_eq(float(_bot.producer_values([FACTORY])[FACTORY]), 0.0)
