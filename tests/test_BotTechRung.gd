extends GutTest
## THE TECH RUNG. A tech structure is one some unit requires; the bot buys it when the best
## unit behind it would be worth `tech_value_margin` times the best it can train today, at a
## producer it owns. Pinned because the ladder had no such rung and every piece behind a tech
## building was unreachable in play however the bot valued it.
##
## Fixtures are stubs on the tests/test_BotIncomeTarget.gd pattern. The tech tree is REAL:
## TechnologySpec with a prerequisite starts locked, so has_tech_for and
## unit_requires_structure are the bot's own.

const RESERVE: int = 600
const TECH: StringName = &"test_tech"
const REDOUBT: StringName = &"test_redoubt"
const RECRUIT: StringName = &"test_recruit"
const GUARD: StringName = &"test_guard"  # behind TECH


class FakeBot:
	extends Bot
	var owned: Dictionary = {}  # structure type -> count
	var values: Dictionary = {}  # unit type -> composition value
	var producible: Array = [RECRUIT, GUARD]

	func can_afford(_a_type: StringName) -> bool:
		return true

	func needs_infrastructure_provider() -> bool:
		return false

	func buildable_structure_types() -> Array:
		return [TECH, REDOUBT]

	func buildable_defence_structure_types() -> Array:
		return []

	func buildable_production_structure_types() -> Array:
		return [REDOUBT]

	func get_structures_of_type(a_type: StringName) -> Array:
		var out: Array = []
		for i: int in int(owned.get(a_type, 0)):
			out.append(null)
		return out

	func enemy_demand_map() -> Dictionary:
		return {&"enemy": {"demand": 1.0, "rep": null}}

	func unit_composition_value(a_unit_type, _a_demand: Dictionary) -> float:
		return float(values.get(a_unit_type, 0.0))

	func unit_can_attack(_a_type) -> bool:
		return true

	var _producer: Actor = null

	func get_production_structures() -> Array:
		if _producer == null:
			_producer = Actor.new()
			_producer.production = Production.new()
			_producer.add_child(_producer.production)
		_producer.production.producible_types.assign(producible)
		return [_producer]

	func release() -> void:
		if _producer != null:
			_producer.free()
			_producer = null


class StubActuator:
	extends BotActuator
	var builds: Array = []

	func build(
		_a_builder: Actor, a_type: StringName, _a_pos: Vector3, _a_quarter_turns: int = 0
	) -> bool:
		builds.append(a_type)
		return true


class StubEconomy:
	extends BotEconomy
	var builder: Actor

	func _construction_job_count() -> int:
		return 0

	func _release_stalled_construction() -> void:
		pass

	func _pick_builder() -> Actor:
		return builder

	func _dominion_structure_to_build() -> Variant:
		return null

	func _infrastructure_structure_to_build() -> Variant:
		return null

	func _extend_dominion(_a_builder: Actor) -> bool:
		return false

	func _income_structure_to_build() -> Variant:
		return null

	func _types_under_way() -> Array[StringName]:
		return []

	func _find_build_spot(_a_type: StringName) -> Variant:
		return Vector3.ZERO


var _bot: FakeBot
var _act: StubActuator


func before_each() -> void:
	_bot = FakeBot.new()
	_bot.technology_mapping = {
		TECH: TechnologySpec.new(800, 0, 0, 30),
		REDOUBT: TechnologySpec.new(300, 0, 0, 30),
		RECRUIT: TechnologySpec.new(100, 0, 0, 30),
		GUARD: TechnologySpec.new(200, 0, 0, 30, [TECH]),
	}
	_bot.values = {RECRUIT: 1.0, GUARD: 2.0}
	_bot.energy = 5000
	_act = StubActuator.new(null)


func after_each() -> void:
	_bot.release()
	_bot.free()


func _economy() -> StubEconomy:
	var economy := StubEconomy.new(_bot, _act)
	economy.reserve = RESERVE
	economy.income_structure_target = 0
	economy.tech_value_margin = 1.3
	economy.builder = autofree(Actor.new()) as Actor
	economy._prev_energy = _bot.energy  # in surplus, so the capacity rung is live
	return economy


func test_a_unit_worth_the_margin_more_buys_the_structure_that_unlocks_it() -> void:
	_economy().tick()
	assert_eq(_act.builds, [TECH], "the Guard is twice the Recruit; 2.0 >= 1.3")


func test_below_the_margin_the_ladder_buys_capacity_instead() -> void:
	_bot.values[GUARD] = 1.2
	_economy().tick()
	assert_eq(_act.builds, [REDOUBT])


func test_a_unit_no_owned_producer_trains_unlocks_nothing_for_this_bot() -> void:
	_bot.producible = [RECRUIT]
	_economy().tick()
	assert_eq(_act.builds, [REDOUBT], "an Operations Center for an aircraft with no airfield")


func test_an_owned_tech_structure_is_not_bought_again() -> void:
	_bot.owned = {TECH: 1}
	_economy().tick()
	assert_eq(_act.builds, [REDOUBT])


func test_tech_the_bot_is_saving_for_is_bought_without_a_surplus() -> void:
	# A falling balance used to rule tech out altogether — and with producers spending every
	# think the balance always fell, so no tech structure was ever built (2026-10-07).
	var economy := _economy()
	economy._prev_energy = _bot.energy + 1  # the balance is falling: not a surplus
	economy.tick()
	assert_eq(_act.builds, [TECH], "the bank was held for it, so it is bought")
	assert_eq(_bot.savings.goal(), &"", "and bought, it is no longer saved for")


func test_without_a_surplus_tech_that_is_not_the_goal_waits() -> void:
	var economy := _economy()
	economy._prev_energy = _bot.energy + 1
	_bot.savings.propose(&"production", &"fake_dearer_wish", 1.0e9, 1)
	economy.tick()
	assert_ne(_bot.savings.goal(), TECH)
	assert_false(_act.builds.has(TECH), "something worth more holds the bank")


func test_the_tech_decision_is_in_the_ledger() -> void:
	_economy().tick()
	var choices: Dictionary = _act.usage.choices()["tech_structure"]
	assert_eq(choices[String(TECH)]["chosen"], 1)
	assert_almost_eq(choices[String(TECH)]["score_sum"], 2.0, 0.001, "the best unit behind it")
	assert_false(choices.has(String(REDOUBT)), "a producer unlocks nothing; not a tech candidate")
