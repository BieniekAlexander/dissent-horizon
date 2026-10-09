extends GutTest

## THE POSTURE LAYER'S PURE CORE (BotPosture; gdd/systems/ai/objective-selection.md): each dial
## is its bias plus its gains times the signals it reads, clamped; a dial holds until its
## target has stood outside the dead band for the hold and then snaps; and a dial divides the
## parameters it reaches by 2^(2d − 1), leaving sentinels alone.
##
## Run with:
##   godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_BotPosture.gd -gexit


func _posture(a_dead_band: float = 0.1, a_hold: float = 10.0) -> BotPosture:
	var posture := BotPosture.new()
	posture.dead_band = a_dead_band
	posture.hold_seconds = a_hold
	return posture


func _dials(a_posture: BotPosture) -> PackedFloat64Array:
	return a_posture.targets_for({}) if false else PackedFloat64Array(a_posture.dials().values())


# ─── THE MAPPING ─────────────────────────────────────────────────────────────


func test_with_no_gains_every_dial_rests_at_its_bias() -> void:
	var posture: BotPosture = _posture()
	posture.commitment_bias = 0.2
	posture.risk_bias = 0.9
	var targets: PackedFloat64Array = posture.targets_for(
		{"economy_lead": 1.0, "army_lead": -1.0, "momentum": 1.0, "stale": 1.0}
	)
	assert_eq(targets, PackedFloat64Array([0.2, 0.5, 0.9, 0.5]))


func test_each_gain_reaches_only_its_own_dial() -> void:
	var posture: BotPosture = _posture()
	posture.commitment_economy_gain = 0.3
	posture.aggression_army_gain = 0.2
	posture.aggression_exposure_gain = -0.1
	posture.risk_momentum_gain = -0.2
	posture.risk_threat_gain = -0.1
	posture.curiosity_stale_gain = 0.4
	var signals: Dictionary = {
		"economy_lead": 1.0,
		"army_lead": 0.5,
		"exposure": 1.0,
		"momentum": 0.5,
		"threat": 1.0,
		"stale": 0.5,
	}
	var targets: PackedFloat64Array = posture.targets_for(signals)
	assert_almost_eq(targets[BotPosture.Dial.COMMITMENT], 0.8, 1e-9)
	assert_almost_eq(targets[BotPosture.Dial.AGGRESSION], 0.5, 1e-9, "0.5 + 0.1 − 0.1")
	assert_almost_eq(targets[BotPosture.Dial.RISK], 0.3, 1e-9, "0.5 − 0.1 − 0.1")
	assert_almost_eq(targets[BotPosture.Dial.CURIOSITY], 0.7, 1e-9)


func test_a_target_is_clamped_to_the_dial_and_a_missing_signal_reads_zero() -> void:
	var posture: BotPosture = _posture()
	posture.commitment_economy_gain = 1.0
	assert_eq(posture.targets_for({"economy_lead": 3.0})[0], 1.0)
	assert_eq(posture.targets_for({"economy_lead": -3.0})[0], 0.0)
	assert_eq(posture.targets_for({})[0], 0.5)


func test_read_params_takes_the_difficulty_fields() -> void:
	var config := BotDifficulty.new()
	config.aggression_army_gain = 0.7
	config.curiosity_bias = 0.1
	config.posture_dead_band = 0.05
	config.posture_hold_seconds = 3.0
	var posture := BotPosture.new()
	posture.read_params(config)
	assert_eq(posture.aggression_army_gain, 0.7)
	assert_eq(posture.curiosity_bias, 0.1)
	assert_eq(posture.dead_band, 0.05)
	assert_eq(posture.hold_seconds, 3.0)


# ─── HYSTERESIS ──────────────────────────────────────────────────────────────


func test_before_any_update_every_dial_is_neutral_and_multiplies_by_one() -> void:
	var posture: BotPosture = _posture()
	for dial: int in BotPosture.DIAL_COUNT:
		assert_eq(posture.dial(dial as BotPosture.Dial), BotPosture.NEUTRAL)
		assert_eq(posture.factor(dial as BotPosture.Dial), 1.0)


func test_the_first_update_snaps_outright() -> void:
	var posture: BotPosture = _posture()
	posture.curiosity_stale_gain = 1.0
	assert_true(posture.update({"stale": 0.4}, 0.0))
	assert_almost_eq(posture.dial(BotPosture.Dial.CURIOSITY), 0.9, 1e-9)


func test_a_target_inside_the_dead_band_never_moves_the_dial() -> void:
	var posture: BotPosture = _posture(0.1, 10.0)
	posture.curiosity_stale_gain = 1.0
	posture.update({"stale": 0.0}, 0.0)
	for t: int in range(1, 100):
		assert_false(posture.update({"stale": 0.09}, float(t)), "wobble at %d s" % t)
	assert_eq(posture.dial(BotPosture.Dial.CURIOSITY), 0.5)


func test_a_target_outside_the_band_is_taken_after_the_hold_and_snaps_to_it() -> void:
	var posture: BotPosture = _posture(0.1, 10.0)
	posture.curiosity_stale_gain = 1.0
	posture.update({"stale": 0.0}, 0.0)
	assert_false(posture.update({"stale": 0.3}, 5.0), "leaves the band at 5 s")
	assert_false(posture.update({"stale": 0.3}, 14.0), "held 9 s")
	assert_eq(posture.dial(BotPosture.Dial.CURIOSITY), 0.5, "still held")
	assert_true(posture.update({"stale": 0.4}, 15.0), "held 10 s: snaps")
	assert_almost_eq(posture.dial(BotPosture.Dial.CURIOSITY), 0.9, 1e-9, "to the target now")


func test_a_target_that_returns_inside_the_band_resets_the_hold() -> void:
	var posture: BotPosture = _posture(0.1, 10.0)
	posture.curiosity_stale_gain = 1.0
	posture.update({"stale": 0.0}, 0.0)
	posture.update({"stale": 0.3}, 1.0)
	posture.update({"stale": 0.0}, 8.0)
	assert_false(posture.update({"stale": 0.3}, 12.0), "a fresh excursion at 12 s")
	assert_false(posture.update({"stale": 0.3}, 21.0), "held 9 s of the new excursion")
	assert_true(posture.update({"stale": 0.3}, 22.0))


func test_a_zero_hold_follows_the_target_at_once() -> void:
	var posture: BotPosture = _posture(0.1, 0.0)
	posture.curiosity_stale_gain = 1.0
	posture.update({"stale": 0.0}, 0.0)
	assert_true(posture.update({"stale": 0.3}, 1.0))
	assert_almost_eq(posture.dial(BotPosture.Dial.CURIOSITY), 0.8, 1e-9)


func test_the_readout_reports_when_a_held_out_target_snaps() -> void:
	var posture: BotPosture = _posture(0.1, 10.0)
	posture.curiosity_stale_gain = 1.0
	posture.update({"stale": 0.0}, 0.0)
	posture.update({"stale": 0.3}, 4.0)
	var curiosity: Dictionary = posture.debug_state(7.0)[BotPosture.Dial.CURIOSITY]
	assert_almost_eq(float(curiosity["snaps_in"]), 7.0, 1e-9)
	assert_eq(float(posture.debug_state(7.0)[BotPosture.Dial.RISK]["snaps_in"]), -1.0)


# ─── MODULATION ──────────────────────────────────────────────────────────────


func test_the_factor_runs_from_half_to_double_through_one() -> void:
	assert_almost_eq(BotPosture.factor_of(0.0), 0.5, 1e-9)
	assert_almost_eq(BotPosture.factor_of(0.5), 1.0, 1e-9)
	assert_almost_eq(BotPosture.factor_of(1.0), 2.0, 1e-9)


func _snapped_to(a_dial: BotPosture.Dial, a_value: float) -> BotPosture:
	# A gain of 1 on the dial's first signal and a bias of 0 puts the dial at the signal.
	var posture: BotPosture = _posture(0.0, 0.0)
	var gain: String = (
		[
			"commitment_economy_gain",
			"aggression_army_gain",
			"risk_momentum_gain",
			"curiosity_stale_gain"
		]
		. get(a_dial)
	)
	var bias: String = ["commitment_bias", "aggression_bias", "risk_bias", "curiosity_bias"][a_dial]
	var signal_key: String = ["economy_lead", "army_lead", "momentum", "stale"][a_dial]
	posture.set(gain, 1.0)
	posture.set(bias, 0.0)
	posture.update({signal_key: a_value}, 0.0)
	return posture


func test_a_neutral_posture_plays_the_config_exactly() -> void:
	var config: BotDifficulty = BotDifficulty.for_tier(PlayerSlot.Difficulty.HARD)
	var played: BotDifficulty = _posture().applied_to(config)
	assert_eq(played.army_commit_threshold, config.army_commit_threshold)
	assert_eq(played.attack_value_ratio, config.attack_value_ratio)
	assert_eq(played.economy_reserve, config.economy_reserve)
	assert_eq(played.income_structure_target, config.income_structure_target)


func test_all_in_halves_what_commitment_reaches_and_leaves_the_config_itself_alone() -> void:
	var config: BotDifficulty = BotDifficulty.for_tier(PlayerSlot.Difficulty.MEDIUM)
	config.income_structure_target = 4
	config.army_commit_threshold = 6
	var played: BotDifficulty = _snapped_to(BotPosture.Dial.COMMITMENT, 1.0).applied_to(config)
	assert_eq(played.income_structure_target, 2)
	assert_eq(played.army_commit_threshold, 3)
	assert_eq(played.attack_value_ratio, config.attack_value_ratio, "not commitment's")
	assert_eq(config.income_structure_target, 4, "the given config is untouched")


func test_offence_lowers_the_commit_ratio_and_the_guard_within_their_ranges() -> void:
	var config: BotDifficulty = BotDifficulty.for_tier(PlayerSlot.Difficulty.MEDIUM)
	config.attack_value_ratio = 1.0
	config.guard_strength_ratio = 3.0
	var played: BotDifficulty = _snapped_to(BotPosture.Dial.AGGRESSION, 1.0).applied_to(config)
	assert_almost_eq(played.attack_value_ratio, 0.8, 1e-9, "halved, then clamped to the range")
	assert_almost_eq(played.guard_strength_ratio, 1.5, 1e-9)


func test_caution_doubles_the_reserve_up_to_its_range() -> void:
	var config: BotDifficulty = BotDifficulty.for_tier(PlayerSlot.Difficulty.MEDIUM)
	config.economy_reserve = 900
	var played: BotDifficulty = _snapped_to(BotPosture.Dial.RISK, 0.0).applied_to(config)
	assert_eq(played.economy_reserve, 1500, "doubled to 1800, clamped to the range")


func test_a_sentinel_is_never_modulated() -> void:
	var config: BotDifficulty = BotDifficulty.for_tier(PlayerSlot.Difficulty.PASSIVE)
	var played: BotDifficulty = _snapped_to(BotPosture.Dial.COMMITMENT, 1.0).applied_to(config)
	assert_eq(played.army_commit_threshold, config.army_commit_threshold, "9999 stays 9999")


func test_the_dials_read_by_name() -> void:
	var posture: BotPosture = _snapped_to(BotPosture.Dial.RISK, 0.25)
	var dials: Dictionary = posture.dials()
	assert_eq(dials.keys(), ["commitment", "aggression", "risk", "curiosity"])
	assert_almost_eq(float(dials["risk"]), 0.25, 1e-9)
