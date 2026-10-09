extends GutTest

## THE ENEMY INCOME ESTIMATE (BotIncome; gdd/systems/ai/objective-selection.md §The economy
## signals): a prior — a personality share of the bot's own income, spread over the shelter
## bands the enemy could have started in — that what the bot has seen replaces band by band,
## as far as each band has been freshly scouted. Pure rules, exercised with no scene.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_BotIncome.gd -gexit


func _band(a_coverage: float, a_observed: float) -> Dictionary:
	return {"centre": Vector2.ZERO, "coverage": a_coverage, "observed": a_observed}


func test_an_unscouted_map_is_the_prior() -> void:
	assert_almost_eq(
		BotIncome.estimate(12.0, [_band(0.0, 0.0), _band(0.0, 0.0)], 0.0, 1.0), 12.0, 1e-9
	)


func test_a_fully_scouted_band_is_what_was_seen_there() -> void:
	# Two bands share a prior of 12: the scouted one contributes its 20 seen, the other its 6.
	assert_almost_eq(
		BotIncome.estimate(12.0, [_band(1.0, 20.0), _band(0.0, 0.0)], 0.0, 1.0), 26.0, 1e-9
	)


func test_a_half_scouted_band_keeps_half_its_share_beside_what_was_seen() -> void:
	assert_almost_eq(
		BotIncome.estimate(12.0, [_band(0.5, 5.0), _band(0.0, 0.0)], 0.0, 1.0), 14.0, 1e-9
	)


func test_what_was_seen_outside_every_band_counts_whole() -> void:
	assert_almost_eq(BotIncome.estimate(12.0, [_band(0.0, 0.0)], 7.0, 1.0), 19.0, 1e-9)


func test_with_no_bands_the_prior_is_scaled_by_the_stale_fraction() -> void:
	assert_almost_eq(BotIncome.estimate(12.0, [], 3.0, 0.25), 6.0, 1e-9)


func test_the_lead_runs_from_minus_one_to_one_and_is_zero_with_nothing() -> void:
	assert_eq(BotIncome.lead(0.0, 0.0), 0.0)
	assert_eq(BotIncome.lead(10.0, 0.0), 1.0)
	assert_eq(BotIncome.lead(0.0, 10.0), -1.0)
	assert_almost_eq(BotIncome.lead(15.0, 5.0), 0.5, 1e-9)


func test_the_candidate_bands_are_every_shelter_but_the_bots_own() -> void:
	var shelters: Array = [Vector2(10.0, 0.0), Vector2(90.0, 0.0), Vector2(50.0, 80.0)]
	assert_eq(
		BotIncome.candidate_shelters(shelters, Vector2(5.0, 0.0)),
		[Vector2(90.0, 0.0), Vector2(50.0, 80.0)]
	)
	assert_eq(BotIncome.candidate_shelters([Vector2(10.0, 0.0)], Vector2.ZERO), [], "one is own")
	assert_eq(BotIncome.candidate_shelters([], Vector2.ZERO), [])


func test_an_observation_goes_to_the_nearest_band_within_the_radius_else_elsewhere() -> void:
	var shelters: Array = [Vector2(0.0, 0.0), Vector2(100.0, 0.0)]
	var observations: Array = [
		{"xz": Vector2(5.0, 0.0), "rate": 5.0},
		{"xz": Vector2(60.0, 0.0), "rate": 15.0},  # 40 from the second: inside a radius of 40
		{"xz": Vector2(50.0, 50.0), "rate": 1.0},  # ~70 from both: outside
	]
	var apportioned: Dictionary = BotIncome.apportion(shelters, observations, 40.0)
	assert_eq(apportioned["bands"][0]["observed"], 5.0)
	assert_eq(apportioned["bands"][1]["observed"], 15.0)
	assert_eq(apportioned["elsewhere"], 1.0)


## Enough of a Bot for the live path: its own income, and nothing seen or scouted.
class StubBot:
	extends Bot
	var income: float = 20.0

	func energy_collection_rate() -> float:
		return income

	func base_centroid() -> Vector3:
		return Vector3.ZERO


func test_outside_a_scene_with_nothing_scouted_the_estimate_is_the_parity_share() -> void:
	var bot: StubBot = autofree(StubBot.new()) as StubBot
	var income := BotIncome.new(bot, null)
	income.assumed_enemy_income_parity = 0.75
	assert_almost_eq(income.enemy_rate_estimate(), 15.0, 1e-9)
	assert_almost_eq(income.economy_lead(), 5.0 / 35.0, 1e-9)
