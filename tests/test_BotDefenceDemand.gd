extends GutTest

## THE STATIC-DEFENCE DEMAND READ: per own region, the value standing there × how vulnerable
## it is — even sides make a region vulnerable, one side having it makes it safe or lost, and
## nobody there makes it nothing (world-model.md §L3; BotEconomy._defence_demand). The read
## is what replaced the count of turrets wanted, so it is pinned on positioned fixtures: every
## quantity here is a cost at a place.

const STRUCTURE_COST: int = 1000
const UNIT_COST: int = 100
const TOWER_COST: int = 400
const HOUSE: StringName = &"test_house"
const TOWER: StringName = &"test_tower"
const SOLDIER: StringName = &"test_soldier"
const ENEMY: StringName = &"test_enemy"


class FakeBot:
	extends Bot
	var own_units: Array = []
	var own_structures: Array = []
	var believed: Array = []  # [{"position", "type"}]

	var demand_map: Dictionary = {}

	func get_units() -> Array:
		return own_units

	func enemy_demand_map() -> Dictionary:
		return demand_map

	func buildable_defence_structure_types() -> Array:
		return [TOWER]

	func can_afford(_a_type) -> bool:
		return true

	func type_targets_ground(_a_type) -> bool:
		return true

	func get_structures() -> Array:
		return own_structures

	func believed_armed_enemies() -> Array:
		return believed

	func unit_can_attack(a_type) -> bool:
		return a_type != HOUSE

	func unit_cost(a_unit_type) -> int:
		match a_unit_type:
			HOUSE:
				return STRUCTURE_COST
			TOWER:
				return TOWER_COST
			_:
				return UNIT_COST


var _bot: FakeBot
var _economy: BotEconomy


func before_each() -> void:
	_bot = FakeBot.new()
	_bot.id = 1
	add_child_autofree(_bot)
	_economy = BotEconomy.new(_bot, BotActuator.new(null))


func _structure(a_id: StringName, a_at: Vector3) -> Commandable:
	var piece: Commandable = FakePieces.structure({})
	_bot.add_child(piece)
	piece.id = a_id
	piece.global_position = a_at
	_bot.own_structures.append(piece)
	return piece


func _soldier(a_at: Vector3) -> void:
	var piece: Commandable = FakePieces.unit({})
	_bot.add_child(piece)
	piece.id = SOLDIER
	piece.global_position = a_at
	_bot.own_units.append(piece)


func _enemy(a_at: Vector3) -> void:
	_bot.believed.append({"position": a_at, "type": ENEMY})


func test_a_region_nobody_contests_wants_nothing() -> void:
	_structure(HOUSE, Vector3.ZERO)
	assert_eq(_economy._defence_demand(), {}, "no influence at all: no opening tower")


func test_a_region_held_by_us_alone_is_safe() -> void:
	_structure(HOUSE, Vector3.ZERO)
	_soldier(Vector3(2.0, 0.0, 0.0))
	assert_eq(_economy._defence_demand(), {}, "our side has it: nothing to contest")


func test_a_region_the_enemy_alone_stands_in_is_lost_not_vulnerable() -> void:
	_structure(HOUSE, Vector3.ZERO)
	_enemy(Vector3(2.0, 0.0, 0.0))
	assert_eq(_economy._defence_demand(), {})


func test_even_sides_make_the_whole_value_the_demand() -> void:
	_structure(HOUSE, Vector3.ZERO)
	_soldier(Vector3(2.0, 0.0, 0.0))
	_enemy(Vector3(5.0, 0.0, 0.0))
	var read: Dictionary = _economy._defence_demand()
	assert_almost_eq(float(read["demand"]), float(STRUCTURE_COST), 0.001, "1000 × 1")
	assert_eq(read["anchor"], Vector2.ZERO)


func test_a_lopsided_fight_is_less_vulnerable_than_an_even_one() -> void:
	_structure(HOUSE, Vector3.ZERO)
	_soldier(Vector3(2.0, 0.0, 0.0))
	_enemy(Vector3(5.0, 0.0, 0.0))
	_enemy(Vector3(6.0, 0.0, 0.0))
	_enemy(Vector3(7.0, 0.0, 0.0))
	# own 100, enemy 300: (400 − 200) / 400 = 0.5
	assert_almost_eq(float(_economy._defence_demand()["demand"]), 500.0, 0.001)


func test_value_is_what_stands_in_the_region_not_the_whole_base() -> void:
	_structure(HOUSE, Vector3.ZERO)
	_structure(HOUSE, Vector3(5.0, 0.0, 0.0))
	_structure(HOUSE, Vector3(100.0, 0.0, 0.0))  # far away: another region
	_soldier(Vector3(2.0, 0.0, 0.0))
	_enemy(Vector3(5.0, 0.0, 0.0))
	assert_almost_eq(float(_economy._defence_demand()["demand"]), 2000.0, 0.001, "two houses")


func test_the_region_asking_the_most_is_the_one_answered() -> void:
	_structure(HOUSE, Vector3.ZERO)
	_soldier(Vector3(2.0, 0.0, 0.0))
	_enemy(Vector3(5.0, 0.0, 0.0))  # even: 1000
	_structure(HOUSE, Vector3(100.0, 0.0, 0.0))
	_structure(HOUSE, Vector3(105.0, 0.0, 0.0))
	_soldier(Vector3(102.0, 0.0, 0.0))
	_enemy(Vector3(104.0, 0.0, 0.0))  # even, and twice the value: 2000
	assert_eq(_economy._defence_demand()["anchor"], Vector2(100.0, 0.0))


func test_a_turret_built_there_counts_toward_our_side_so_the_remaining_demand_falls() -> void:
	_structure(HOUSE, Vector3.ZERO)
	_soldier(Vector3(2.0, 0.0, 0.0))
	_enemy(Vector3(5.0, 0.0, 0.0))
	var before: float = float(_economy._defence_demand()["demand"])
	_structure(TOWER, Vector3(3.0, 0.0, 0.0))
	var after: float = float(_economy._defence_demand()["demand"])
	# own 500 against enemy 100 over a value of 1400: (600 − 400) / 600 × 1400 ≈ 467
	assert_lt(after, before, "the first turret answers most of the demand")
	assert_almost_eq(after, 1400.0 / 3.0, 0.01)


func test_a_believed_enemy_beyond_the_region_weighs_nothing() -> void:
	_structure(HOUSE, Vector3.ZERO)
	_soldier(Vector3(2.0, 0.0, 0.0))
	_enemy(Vector3(BotEconomy.DEFENCE_REGION_RADIUS + 1.0, 0.0, 0.0))
	assert_eq(_economy._defence_demand(), {})


## A believed type that has gone extinct carries a null rep (Bot.enemy_demand_map); choosing a
## defence must read past it rather than dereference it.
func test_an_extinct_believed_type_does_not_stop_a_defence_being_chosen() -> void:
	_bot.energy = TOWER_COST + _economy.reserve
	_bot.demand_map = {ENEMY: {"demand": 1.0, "rep": null}}
	assert_eq(_economy._defence_structure_to_build(), TOWER)


func test_every_contested_region_is_reported_with_its_terms() -> void:
	_structure(HOUSE, Vector3.ZERO)
	_soldier(Vector3(2.0, 0.0, 0.0))
	_enemy(Vector3(5.0, 0.0, 0.0))
	_structure(HOUSE, Vector3(100.0, 0.0, 0.0))  # nobody there: no tension, not reported
	var regions: Array = _economy.defence_demand_by_region()
	assert_eq(regions.size(), 1)
	assert_eq(regions[0]["centre"], Vector3.ZERO)
	assert_almost_eq(float(regions[0]["value"]), float(STRUCTURE_COST), 0.001)
	assert_almost_eq(float(regions[0]["own"]), float(UNIT_COST), 0.001)
	assert_almost_eq(float(regions[0]["enemy"]), float(UNIT_COST), 0.001)
	assert_almost_eq(float(regions[0]["demand"]), float(STRUCTURE_COST), 0.001)
