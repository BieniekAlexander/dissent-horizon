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
