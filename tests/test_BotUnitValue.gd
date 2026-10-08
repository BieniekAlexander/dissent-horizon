extends GutTest

## WHAT ONE ENERGY OF A UNIT BUYS (Bot.unit_strength_per_energy_vs): √(dps × matchup × hp ÷
## the target's multiplier against it) ÷ cost — Lanchester's square law, so two buys of equal
## energy compare by it. The bare matchup it replaced priced nothing, and the bot bought the
## cheapest unit with a fair matchup every time (gdd/systems/ai/bot-architecture.md).
##
## The previews, costs and both multipliers are the fake bot's, so what is pinned is the
## arithmetic, not the damage table's authored profiles.

const CHEAP: StringName = &"fake_cheap"
const DEAR: StringName = &"fake_dear"


class FakeBot:
	extends Bot
	var previews: Dictionary = {}  # type -> preview
	var costs: Dictionary = {}  # type -> energy
	var incoming: Dictionary = {}  # type -> the target's multiplier against it

	func _preview_for_type(a_type) -> Node:
		return previews.get(a_type)

	func unit_cost(a_type) -> int:
		return costs.get(a_type, 0)

	func unit_effectiveness_vs(_a_type, _a_target: Commandable) -> float:
		return 1.0

	func _incoming_multiplier(_a_attacker: Commandable, a_victim: Node) -> float:
		for type: StringName in previews:
			if previews[type] == a_victim:
				return incoming.get(type, 1.0)
		return 1.0


var _bot: FakeBot
var _target: Commandable


func before_each() -> void:
	_bot = FakeBot.new()
	add_child_autofree(_bot)
	_target = FakePieces.unit({"weapon": {"damage": 5.0, "ground": 5.0}})
	add_child_autofree(_target)


## A preview of a unit with `a_hp` and a gun of `a_damage` a hit, costing `a_cost`.
func _type(a_type: StringName, a_hp: float, a_damage: float, a_cost: int) -> Commandable:
	var preview: Commandable = FakePieces.unit({"hp": a_hp, "weapon": {"damage": a_damage}})
	autofree(preview)
	_bot.previews[a_type] = preview
	_bot.costs[a_type] = a_cost
	return preview


func _dps(a_preview: Commandable) -> float:
	return (a_preview.get_node("Loadout") as Loadout).get_weapons()[0].approximate_dps()


func test_the_value_is_the_root_of_dps_times_toughness_over_cost() -> void:
	var cheap: Commandable = _type(CHEAP, 120.0, 7.5, 100)
	_bot.incoming[CHEAP] = 0.5
	assert_almost_eq(
		_bot.unit_strength_per_energy_vs(CHEAP, _target),
		sqrt(_dps(cheap) * 120.0 / 0.5) / 100.0,
		0.0001
	)


func test_armour_is_what_makes_the_dear_unit_the_better_buy() -> void:
	# The Recruit and the anti-light vehicle in miniature: five times the price, five times the
	# gun, two and a half times the hull.
	_type(CHEAP, 120.0, 7.5, 100)
	_type(DEAR, 300.0, 37.5, 500)
	_bot.incoming[CHEAP] = 1.0
	_bot.incoming[DEAR] = 1.0
	assert_gt(
		_bot.unit_strength_per_energy_vs(CHEAP, _target),
		_bot.unit_strength_per_energy_vs(DEAR, _target),
		"unarmoured, the cheap unit buys more fight"
	)
	_bot.incoming[DEAR] = 0.24  # the enemy's guns barely scratch it
	assert_gt(
		_bot.unit_strength_per_energy_vs(DEAR, _target),
		_bot.unit_strength_per_energy_vs(CHEAP, _target),
		"armoured against what it faces, the dear one does"
	)


func test_a_target_that_cannot_hurt_the_unit_does_not_make_it_invulnerable() -> void:
	_type(CHEAP, 120.0, 7.5, 100)
	_bot.incoming[CHEAP] = 0.0
	var floored: float = _bot.unit_strength_per_energy_vs(CHEAP, _target)
	_bot.incoming[CHEAP] = Bot.MIN_INCOMING_MULTIPLIER
	assert_almost_eq(floored, _bot.unit_strength_per_energy_vs(CHEAP, _target), 0.0001)
	assert_true(is_finite(floored))


func test_an_unpriced_or_unknown_type_is_worth_nothing() -> void:
	_type(CHEAP, 120.0, 7.5, 0)
	assert_eq(_bot.unit_strength_per_energy_vs(CHEAP, _target), 0.0, "no cost, no rate")
	assert_eq(_bot.unit_strength_per_energy_vs(&"fake_absent", _target), 0.0, "no preview")
