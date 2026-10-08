extends GutTest

## THE STATIC-DEFENCE RUNG buys a turret between income and throughput when the demand read
## (value × vulnerability of a region, tests/test_BotDefenceDemand.gd) clears the gun's cost
## times `defence_propensity`, only once a producer stands, and picks the type whose gun
## answers the enemy UNITS it has seen. Pinned here because the ladder had no such rung at all
## and the bot never built a turret however cheaply it traded — a rung that is not pinned can
## fall out again unnoticed. The demand itself is stubbed: what is under test is the rung.
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
	var own_units: Array = []
	var demand_seen: Dictionary = {}  # what the defence choice was scored against
	var condition: Scenario.WinCondition = Scenario.WinCondition.MISSION
	var centres: Array = []
	var frontmost: Commandable = null

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

	func unit_composition_value(a_unit_type, a_demand: Dictionary) -> float:
		demand_seen = a_demand
		return float(values.get(a_unit_type, 0.0))

	func get_units() -> Array:
		return own_units

	func unit_can_attack(a_type) -> bool:
		return a_type != &"test_truck"

	func type_targets_ground(a_type) -> bool:
		return a_type != SAM

	func win_condition() -> Scenario.WinCondition:
		return condition

	func owned_command_centres() -> Array:
		return centres

	func frontmost_structure(_a_direction: Vector2) -> Commandable:
		return frontmost

	func base_centroid() -> Vector3:
		return Vector3.ZERO

	func threat_direction(_a_from_xz: Vector2) -> Vector2:
		return Vector2(1.0, 0.0)


class StubActuator:
	extends BotActuator
	var builds: Array = []

	func build(_a_builder: Commandable, a_type: StringName, _a_pos: Vector3) -> bool:
		builds.append(a_type)
		return true


class StubEconomy:
	extends BotEconomy
	var builder: Commandable
	## What the demand read answers; a tower costs 400 here, so the default clears it.
	var demand_read: Dictionary = {"anchor": Vector2.ZERO, "demand": 1000.0}

	func _defence_demand() -> Dictionary:
		return demand_read

	func _construction_job_count() -> int:
		return 0

	func _release_stalled_construction() -> void:
		pass  # reads each unit's command; the fixture units are out of tree and have none

	func _abort_contested_jobs() -> void:
		pass  # likewise

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


func test_a_defence_is_bought_before_more_throughput_while_the_demand_clears_its_cost() -> void:
	var economy := _economy()
	economy.tick()
	assert_eq(_act.builds, [TOWER], "the turret comes before the second barracks")


func test_a_demand_below_the_cost_falls_through_to_throughput() -> void:
	var economy := _economy()
	economy.demand_read = {"anchor": Vector2.ZERO, "demand": 300.0}
	economy.tick()
	assert_eq(_act.builds, [REDOUBT])


func test_the_propensity_scales_the_demand() -> void:
	var economy := _economy()
	economy.demand_read = {"anchor": Vector2.ZERO, "demand": 300.0}
	economy.defence_propensity = 2.0
	economy.tick()
	assert_eq(_act.builds, [TOWER], "600 against 400")


func test_a_propensity_of_zero_never_builds_one() -> void:
	var economy := _economy()
	economy.defence_propensity = 0.0
	economy.tick()
	assert_eq(_act.builds, [REDOUBT], "0 is the bot that had no rung")


func test_with_nothing_standing_there_is_no_demand_to_answer() -> void:
	var economy := _economy()
	economy.demand_read = {}
	economy.tick()
	assert_eq(_act.builds, [REDOUBT])


func test_the_turret_is_anchored_on_the_region_that_asked_for_it() -> void:
	var economy := _economy()
	economy.demand_read = {"anchor": Vector2(7.0, 3.0), "demand": 1000.0}
	economy.tick()
	assert_eq(economy._defence_anchor(), Vector2(7.0, 3.0))


func test_no_producer_yet_means_the_producer_comes_first() -> void:
	var economy := _economy()
	_bot.producers_owned = 0
	economy.tick()
	assert_eq(_act.builds, [REDOUBT], "a turret guards a base; there is none to guard")


func test_the_defence_that_answers_the_seen_army_is_the_one_built() -> void:
	var economy := _economy()
	var infantry: Commandable = autofree(Commandable.new())
	_bot.demand = {&"enemy_infantry": {"demand": 1.0, "rep": infantry}}
	_bot.values = {TOWER: 0.2, SAM: 1.0}
	economy.tick()
	assert_eq(_act.builds, [SAM], "the higher composition value wins")


func test_with_nothing_seen_the_bots_own_army_stands_in_for_the_enemys() -> void:
	var economy := _economy()
	var recruit_a: Commandable = autofree(Commandable.new())
	var recruit_b: Commandable = autofree(Commandable.new())
	var truck: Commandable = autofree(Commandable.new())
	recruit_a.id = &"test_recruit"
	recruit_b.id = &"test_recruit"
	truck.id = &"test_truck"
	_bot.own_units = [recruit_a, recruit_b, truck]
	economy.tick()
	assert_eq(_bot.demand_seen.keys(), [&"test_recruit"], "combat units only, one entry per type")
	assert_eq(_bot.demand_seen[&"test_recruit"]["demand"], 2.0, "one unit of importance each")


func test_with_nothing_seen_and_no_army_a_ground_gun_beats_a_cheaper_anti_air_one() -> void:
	var economy := _economy()
	_bot.costs[SAM] = 300
	_bot.technology_mapping[SAM] = TechnologySpec.new(300, 0, 0, 30)
	economy.tick()
	assert_eq(_act.builds, [TOWER], "the first threat in a match walks")


func test_an_unaffordable_defence_falls_through_rather_than_banking() -> void:
	var economy := _economy()
	_bot.energy = 950  # above the reserve by less than a tower, enough for nothing above it
	_bot.costs[REDOUBT] = 100
	_bot.technology_mapping[REDOUBT] = TechnologySpec.new(100, 0, 0, 30)
	economy._prev_energy = _bot.energy
	economy.tick()
	assert_eq(_act.builds, [REDOUBT], "the rung below it still runs")


# ─── WHERE IT STANDS ────────────────────────────────────────────────────────


## In the tree under the bot, because the anchor reads a GLOBAL position, as it does in play.
func _structure_at(a_x: float) -> Commandable:
	var piece: Commandable = FakePieces.structure({})
	if not _bot.is_inside_tree():
		add_child(_bot)
	_bot.add_child(piece)
	piece.global_position = Vector3(a_x, 0.0, 0.0)
	return piece


func test_under_hegemony_the_anchor_is_the_frontmost_command_centre() -> void:
	var economy := _economy()
	_bot.condition = Scenario.WinCondition.HEGEMONY
	_bot.centres = [_structure_at(2.0), _structure_at(5.0)]
	_bot.frontmost = _structure_at(9.0)
	assert_eq(economy._defence_anchor(), Vector2(5.0, 0.0), "the centre nearest the threat")


func test_otherwise_the_anchor_is_the_structure_the_enemy_reaches_first() -> void:
	var economy := _economy()
	_bot.centres = [_structure_at(2.0)]
	_bot.frontmost = _structure_at(9.0)
	assert_eq(economy._defence_anchor(), Vector2(9.0, 0.0))


func test_with_nothing_standing_the_anchor_is_the_base() -> void:
	var economy := _economy()
	assert_eq(economy._defence_anchor(), Vector2.ZERO)
