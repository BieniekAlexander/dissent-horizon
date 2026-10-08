extends GutTest

## The learned combat model's reader: the lookup tables tools/combat_model/train.py exports,
## driven from a hand-built fixture so every number is known.

const CAP: int = 4


## Two types. Owning `tank` helps, facing it hurts; `scout` does little; and a pair term pays
## when own tanks meet enemy scouts.
func _fixture() -> Dictionary:
	return {
		"intercept": 0.05,
		"cap": CAP,
		"types": ["tank", "scout"],
		"main":
		{
			"own:tank": [0.0, 0.2, 0.4, 0.6, 0.8],
			"enemy:tank": [0.0, -0.2, -0.4, -0.6, -0.8],
			"own:scout": [0.0, 0.05, 0.1, 0.15, 0.2],
			"enemy:scout": [0.0, -0.05, -0.1, -0.15, -0.2],
		},
		"pairs":
		[
			{
				"a": "own:tank",
				"b": "enemy:scout",
				"grid":
				[
					[0.0, 0.0, 0.0, 0.0, 0.0],
					[0.0, 0.1, 0.1, 0.1, 0.1],
					[0.0, 0.1, 0.2, 0.2, 0.2],
					[0.0, 0.1, 0.2, 0.3, 0.3],
					[0.0, 0.1, 0.2, 0.3, 0.4],
				],
			}
		],
	}


func test_the_two_sides_are_exactly_opposite() -> void:
	var model: CombatModel = CombatModel.from_dict(_fixture())
	var own: Dictionary = {&"tank": 2}
	var enemy: Dictionary = {&"scout": 3, &"tank": 1}
	assert_almost_eq(model.predict(own, enemy), -model.predict(enemy, own), 1e-6)
	assert_almost_eq(model.predict(own, own), 0.0, 1e-6, "a mirror match is even")


func test_a_pair_term_is_an_interaction_the_main_terms_cannot_make() -> void:
	var model: CombatModel = CombatModel.from_dict(_fixture())
	# Own tank vs enemy scout: main 0.2 − 0.05, pair 0.1; the mirror reads the pair as absent.
	# Averaged with the mirror: ((0.05 + 0.2 − 0.05 + 0.1) − (0.05 + 0.05 − 0.2)) / 2 = 0.2
	assert_almost_eq(model.predict({&"tank": 1}, {&"scout": 1}), 0.2, 1e-6)


func test_one_more_piece_is_worth_the_difference_it_makes() -> void:
	var model: CombatModel = CombatModel.from_dict(_fixture())
	var own: Dictionary = {&"tank": 1}
	var enemy: Dictionary = {&"scout": 2}
	var expected: float = model.predict({&"tank": 2}, enemy) - model.predict(own, enemy)
	assert_almost_eq(model.marginal(own, enemy, &"tank"), expected, 1e-6)
	assert_gt(model.marginal(own, enemy, &"tank"), model.marginal(own, enemy, &"scout"))
	assert_eq(own, {&"tank": 1}, "the caller's composition is not changed")


func test_forces_past_the_cap_are_scaled_together() -> void:
	var model: CombatModel = CombatModel.from_dict(_fixture())
	assert_almost_eq(
		model.predict({&"tank": 8}, {&"scout": 8}),
		model.predict({&"tank": CAP}, {&"scout": CAP}),
		1e-6,
		"the ratio and the mix are kept, the size is not"
	)
	# 6 against 3 scales to 4 against 2.
	assert_almost_eq(
		model.predict({&"tank": 6}, {&"scout": 3}), model.predict({&"tank": 4}, {&"scout": 2}), 1e-6
	)


func test_a_fractional_count_interpolates() -> void:
	var at_half: float = CombatModel._lookup([0.0, 1.0], 0.5)
	assert_almost_eq(at_half, 0.5, 1e-6)
	assert_almost_eq(CombatModel._lookup([0.0, 1.0], 9.0), 1.0, 1e-6, "clamped to the table")


func test_it_knows_only_what_it_was_trained_on() -> void:
	var model: CombatModel = CombatModel.from_dict(_fixture())
	assert_true(model.knows(&"tank"))
	assert_false(model.knows(&"battleship"))
	assert_almost_eq(
		model.predict({&"tank": 1, &"battleship": 3}, {}),
		model.predict({&"tank": 1}, {}),
		1e-6,
		"an unknown type adds nothing"
	)


func test_no_model_is_null_rather_than_an_error() -> void:
	assert_null(CombatModel.from_dict({"intercept": 0.0}))
	assert_null(CombatModel.from_file("res://does/not/exist.json"))
