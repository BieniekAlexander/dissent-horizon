extends GutTest

## THE STATIC-DEFENCE RUNG. `BotDifficulty.defence_structure_target` is how many turrets the
## bot wants standing; the rung buys one between income and throughput, only once a producer
## stands, and picks the type whose gun answers the enemy UNITS it has seen. Pinned here
## because the ladder had no such rung at all and the bot never built a turret however cheaply
## it traded — a rung that is not pinned can fall out again unnoticed.
##
## Fixtures are stubs on the tests/test_BotIncomeTarget.gd pattern: what is under test is
## which rung of `tick()` runs and which type it picks, decided from counts and scores.

const RESERVE: int = 600
const TOWER: StringName = &"test_tower"
const SAM: StringName = &"test_sam"
const REDOUBT: StringName = &"test_redoubt"
const EXTRACTOR: StringName = &"test_extractor"


class FakeBot:
	extends Bot
	var costs: Dictionary = {}
	var defences_owned: Dictionary = {}  # type -> count
	var producers_owned: int = 1
	var demand: Dictionary = {}
	var values: Dictionary = {}  # type -> composition value

	func can_afford(a_type: StringName) -> bool:
		return energy >= int(costs.get(a_type, 0))

	func needs_infrastructure_provider() -> bool:
		return false

	func buildable_defence_structure_types() -> Array:
		return [TOWER, SAM]

	func buildable_production_structure_types() -> Array:
		return [REDOUBT]

	func get_structures_of_type(a_type: StringName) -> Array:
		var out: Array = []
		var n: int = producers_owned if a_type == REDOUBT else int(defences_owned.get(a_type, 0))
		for i: int in n:
			out.append(null)
		return out

	func enemy_demand_map() -> Dictionary:
		return demand

	func unit_composition_value(a_unit_type, _a_demand: Dictionary) -> float:
		return float(values.get(a_unit_type, 0.0))


class StubActuator:
	extends BotActuator
	var builds: Array = []

	func build(_a_builder: Commandable, a_type: StringName, _a_pos: Vector3) -> bool:
		builds.append(a_type)
		return true


class StubEconomy:
	extends BotEconomy
	var builder: Commandable

	func _construction_job_count() -> int:
		return 0

	func _pick_builder() -> Commandable:
		return builder

	func _dominion_structure_to_build() -> Variant:
		return null

	func _infrastructure_structure_to_build() -> Variant:
		return null

	func _production_structure_to_build() -> Variant:
		return REDOUBT

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
	_bot.costs = {TOWER: 400, SAM: 400, REDOUBT: 900}
	_bot.technology_mapping = {
		TOWER: TechnologySpec.new(400, 0, 0, 30),
		SAM: TechnologySpec.new(400, 0, 0, 30),
		REDOUBT: TechnologySpec.new(900, 0, 0, 30),
	}
	_bot.energy = 5000
	_act = StubActuator.new(null)


func after_each() -> void:
	_bot.free()


func _economy() -> StubEconomy:
	var economy := StubEconomy.new(_bot, _act)
	economy.reserve = RESERVE
	economy.income_structure_target = 0
	economy.builder = autofree(Commandable.new()) as Commandable
	economy._prev_energy = _bot.energy  # in surplus, so the capacity rung is live
	return economy


func test_a_defence_is_bought_before_more_throughput_while_below_the_target() -> void:
	var economy := _economy()
	economy.defence_structure_target = 2
	economy.tick()
	assert_eq(_act.builds, [TOWER], "the first turret comes before the second barracks")


func test_at_the_target_the_ladder_falls_through_to_throughput() -> void:
	var economy := _economy()
	economy.defence_structure_target = 1
	_bot.defences_owned = {TOWER: 1}
	economy.tick()
	assert_eq(_act.builds, [REDOUBT])


func test_a_target_of_zero_never_builds_one() -> void:
	var economy := _economy()
	economy.defence_structure_target = 0
	economy.tick()
	assert_eq(_act.builds, [REDOUBT], "0 is the bot that had no rung")


func test_no_producer_yet_means_the_producer_comes_first() -> void:
	var economy := _economy()
	economy.defence_structure_target = 2
	_bot.producers_owned = 0
	economy.tick()
	assert_eq(_act.builds, [REDOUBT], "a turret guards a base; there is none to guard")


func test_the_defence_that_answers_the_seen_army_is_the_one_built() -> void:
	var economy := _economy()
	economy.defence_structure_target = 1
	var infantry: Commandable = autofree(Commandable.new())
	_bot.demand = {&"enemy_infantry": {"demand": 1.0, "rep": infantry}}
	_bot.values = {TOWER: 0.2, SAM: 1.0}
	economy.tick()
	assert_eq(_act.builds, [SAM], "the higher composition value wins")


func test_with_nothing_seen_the_cheaper_defence_is_built() -> void:
	var economy := _economy()
	economy.defence_structure_target = 1
	_bot.costs[SAM] = 300
	_bot.technology_mapping[SAM] = TechnologySpec.new(300, 0, 0, 30)
	economy.tick()
	assert_eq(_act.builds, [SAM])


func test_an_unaffordable_defence_falls_through_rather_than_banking() -> void:
	var economy := _economy()
	economy.defence_structure_target = 1
	_bot.energy = 950  # above the reserve by less than a tower, enough for nothing above it
	_bot.costs[REDOUBT] = 100
	_bot.technology_mapping[REDOUBT] = TechnologySpec.new(100, 0, 0, 30)
	economy._prev_energy = _bot.energy
	economy.tick()
	assert_eq(_act.builds, [REDOUBT], "the rung below it still runs")
