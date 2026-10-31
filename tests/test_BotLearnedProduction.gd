extends GutTest

## THE ONE PURCHASE VALUATION (Bot.purchase_values_per_energy): scored by the combat model when
## the switch is on and the model can score every candidate, and by the demand map otherwise —
## read by the unit choice, the producer rung and the tech rung alike.


class StubBot:
	extends Bot

	## The learned choice reads the clocked composition; this stub has no fields, so its
	## plain counts stand in for the weights.
	func believed_enemy_composition_clocked() -> Dictionary:
		return believed_enemy_composition()

	var own: Dictionary = {}
	var enemy: Dictionary = {}

	func own_armed_composition() -> Dictionary:
		return own

	func believed_enemy_composition() -> Dictionary:
		return enemy

	## What each own type can damage, by enemy type: {own: [enemy, …]}. A type absent here can
	## damage everything, as the real test answers for a type with no preview.
	var hits: Dictionary = {}

	func _preview_for_type(a_type) -> Node:
		return preview if hits.has(a_type) or enemy.has(a_type) else null

	var preview: Node = null

	func type_can_damage(a_type, a_target_type) -> bool:
		return not hits.has(a_type) or (hits[a_type] as Array).has(a_target_type)

	## Every candidate here is armed; what it can hit is `hits`.
	func unit_can_attack(_a_type) -> bool:
		return true


var _bot: StubBot
var _production: BotProduction


func before_each() -> void:
	_bot = StubBot.new()
	add_child_autofree(_bot)
	_bot.technology_mapping[&"tank"] = TechnologySpec.new(400, 0, 0, 30)
	_bot.technology_mapping[&"scout"] = TechnologySpec.new(100, 0, 0, 30)
	_production = BotProduction.new(_bot, BotActuator.new(null))
	_bot.combat_model = (
		CombatModel
		. from_dict(
			{
				"intercept": 0.0,
				"cap": 8,
				"types": ["tank", "scout", "raider"],
				"main":
				{
					"own:tank": [0.0, 0.4, 0.8, 1.2, 1.6, 2.0, 2.4, 2.8, 3.2],
					"own:scout": [0.0, 0.05, 0.1, 0.15, 0.2, 0.25, 0.3, 0.35, 0.4],
					"enemy:raider": [0.0, -0.3, -0.6, -0.9, -1.2, -1.5, -1.8, -2.1, -2.4],
				},
				"pairs": [],
			}
		)
	)
	_bot.should_use_learned_production = true
	_bot.enemy = {&"raider": 3}


func test_each_candidate_is_scored_per_energy_by_the_model() -> void:
	var valued: Dictionary = _bot.purchase_values_per_energy([&"tank", &"scout"])
	assert_true(valued["learned"])
	assert_almost_eq(
		float(valued["values"][&"tank"]),
		0.2 / 400.0,
		1e-9,
		"a tank moves the margin 0.4, halved by the mirror"
	)
	assert_almost_eq(float(valued["values"][&"scout"]), 0.025 / 100.0, 1e-9)


func test_the_switch_off_leaves_the_demand_map_in_charge() -> void:
	_bot.should_use_learned_production = false
	assert_false(_bot.purchase_values_per_energy([&"tank"], _demand())["learned"])


func test_a_candidate_the_model_does_not_know_falls_back_for_the_whole_choice() -> void:
	assert_false(_bot.purchase_values_per_energy([&"tank", &"battleship"], _demand())["learned"])


func test_no_believed_enemy_falls_back() -> void:
	_bot.enemy = {}
	assert_false(_bot.purchase_values_per_energy([&"tank"], _demand())["learned"])


## A demand map the fallback can price against without reps: every value reads 0.
func _demand() -> Dictionary:
	return {&"raider": {"demand": 1.0, "rep": null}}


# ─── INERT PURCHASES ─────────────────────────────────────────────────────────
#
# A unit that cannot damage any believed enemy unit is worth nothing to buy, whatever the
# model says; one that can damage part of them keeps that part (Alex, 2026-10-30).


func _with_previews() -> void:
	_bot.preview = autofree(Node.new())


func test_a_unit_inert_against_everything_believed_is_worth_nothing() -> void:
	_with_previews()
	_bot.hits = {&"tank": [&"flyer"]}  # a tank can only hit a type the enemy has none of
	_bot.enemy = {&"raider": 3}
	var valued: Dictionary = _bot.purchase_values_per_energy([&"tank", &"scout"])
	assert_true(valued["learned"], "the model still priced the choice")
	assert_eq(float(valued["values"][&"tank"]), 0.0, "and the inert tank is cut to nothing")
	assert_almost_eq(
		float(valued["values"][&"scout"]), 0.025 / 100.0, 1e-9, "the scout keeps its value"
	)


## Nothing worth buying is nothing bought (Alex, 2026-10-30): when every candidate is cut to
## 0 the choice must not fall through to the first of them (decision-pathologies.md §Defects 2).
func test_every_candidate_inert_trains_nothing() -> void:
	_with_previews()
	_bot.hits = {&"tank": [&"flyer"], &"scout": [&"flyer"]}
	_bot.enemy = {&"raider": 3}
	var producer: Actor = FakePieces.unit({"produces": ["tank", "scout"]})
	add_child_autofree(producer)
	assert_eq(_production._best_unit_for(producer, {&"raider": 1.0}), &"", "nothing to buy")
	_bot.hits = {&"tank": [&"raider"], &"scout": [&"flyer"]}
	assert_eq(_production._best_unit_for(producer, {&"raider": 1.0}), &"tank", "the one that hits")


func test_a_unit_that_fights_part_of_the_enemy_keeps_that_part() -> void:
	_with_previews()
	_bot.hits = {&"tank": [&"raider"]}
	_bot.enemy = {&"raider": 1, &"flyer": 3}
	assert_almost_eq(_bot.answerable_share(&"tank"), 0.25, 1e-9)
	var valued: Dictionary = _bot.purchase_values_per_energy([&"tank"])
	assert_almost_eq(float(valued["values"][&"tank"]), 0.25 * (0.2 / 400.0), 1e-6)


func test_nothing_believed_leaves_every_value_whole() -> void:
	_with_previews()
	_bot.hits = {&"tank": []}
	_bot.enemy = {}
	assert_eq(_bot.answerable_share(&"tank"), 1.0, "nothing to be inert against")


func test_a_type_without_a_preview_cannot_be_judged_and_is_left_whole() -> void:
	_bot.enemy = {&"raider": 3}
	assert_eq(_bot.answerable_share(&"battleship"), 1.0)


func test_the_cut_applies_on_the_demand_map_too() -> void:
	_with_previews()
	_bot.should_use_learned_production = false
	_bot.hits = {&"tank": []}
	_bot.enemy = {&"raider": 2}
	var valued: Dictionary = _bot.purchase_values_per_energy([&"tank"], _demand())
	assert_false(valued["learned"])
	assert_eq(float(valued["values"][&"tank"]), 0.0)
