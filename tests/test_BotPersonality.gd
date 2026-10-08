extends GutTest

## The bot's own randomness (gdd/systems/ai/bot-randomness.md): a personality drawn once per
## match from the bot's seeded stream, and scored decisions sampled at a temperature. Both
## reproduce from the seed, and both switch off to the deterministic bot the project had.


func _rng(a_seed: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = a_seed
	return rng


func _fields(a_config: BotDifficulty) -> Dictionary:
	var out: Dictionary = {}
	for property: Dictionary in a_config.get_property_list():
		if property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			out[property["name"]] = a_config.get(property["name"])
	return out


# ─── THE PERSONALITY DRAW ────────────────────────────────────────────────────


func test_no_spread_is_the_tier_exactly() -> void:
	var tier := BotDifficulty.for_tier(PlayerSlot.Difficulty.MEDIUM)
	assert_eq(_fields(tier.jittered(_rng(1), 0.0)), _fields(tier))
	assert_eq(_fields(tier.jittered(null, 0.5)), _fields(tier), "no generator draws nothing")


func test_a_draw_moves_the_searchable_fields_and_stays_in_range() -> void:
	var tier := BotDifficulty.for_tier(PlayerSlot.Difficulty.MEDIUM)
	var drawn := tier.jittered(_rng(7), 0.3)
	var moved: int = 0
	for field: String in BotDifficulty.SEARCH_RANGES:
		var lo: float = float(BotDifficulty.SEARCH_RANGES[field][0])
		var hi: float = float(BotDifficulty.SEARCH_RANGES[field][1])
		var value: Variant = drawn.get(field)
		if float(tier.get(field)) < lo or float(tier.get(field)) > hi:
			continue  # a sentinel, checked below
		assert_between(float(value), lo, hi, field)
		assert_eq(typeof(value), typeof(tier.get(field)), "%s keeps its type" % field)
		if value != tier.get(field):
			moved += 1
	assert_gt(moved, 5, "a wide spread moves most of the table")


func test_the_same_seed_is_the_same_personality() -> void:
	var tier := BotDifficulty.for_tier(PlayerSlot.Difficulty.HARD)
	assert_eq(_fields(tier.jittered(_rng(42), 0.2)), _fields(tier.jittered(_rng(42), 0.2)))
	assert_ne(_fields(tier.jittered(_rng(42), 0.2)), _fields(tier.jittered(_rng(43), 0.2)))


func test_sentinels_and_the_tiers_identity_are_never_moved() -> void:
	var passive := BotDifficulty.for_tier(PlayerSlot.Difficulty.PASSIVE)
	var drawn := passive.jittered(_rng(3), 0.5)
	assert_eq(drawn.army_commit_threshold, 9999, "PASSIVE's never-attack sentinel")
	assert_eq(drawn.preserve_min_cost, -1, "the never-preserve sentinel")
	assert_eq(drawn.may_attack, false)
	assert_eq(
		drawn.combat_period_seconds, passive.combat_period_seconds, "reaction time is the tier"
	)
	var impossible := BotDifficulty.for_tier(PlayerSlot.Difficulty.IMPOSSIBLE)
	assert_eq(impossible.jittered(_rng(3), 0.5).build_concurrency, -1, "UNCAPPED stays uncapped")


func test_the_passive_tier_has_no_variety() -> void:
	var passive := BotDifficulty.for_tier(PlayerSlot.Difficulty.PASSIVE)
	assert_eq(passive.personality_spread, 0.0)
	assert_eq(passive.decision_temperature, 0.0)


# ─── THE BRAIN'S STREAM ──────────────────────────────────────────────────────


func test_a_brain_seeded_alike_draws_alike_and_slots_differ() -> void:
	var a := autofree(BotBrain.new()) as BotBrain
	var b := autofree(BotBrain.new()) as BotBrain
	var c := autofree(BotBrain.new()) as BotBrain
	a.seed_randomness(100, 1)
	b.seed_randomness(100, 1)
	c.seed_randomness(100, 2)
	assert_eq(a.rng.randf(), b.rng.randf(), "same match, same slot: same stream")
	assert_ne(a.rng.randf(), c.rng.randf(), "the other slot is another stream")


func test_an_unseeded_brain_keeps_its_tier() -> void:
	var brain := autofree(BotBrain.new()) as BotBrain
	var before: Dictionary = _fields(brain.config)
	brain._draw_personality()
	assert_eq(_fields(brain.config), before)


func test_a_seeded_brain_draws_once() -> void:
	var brain := autofree(BotBrain.new()) as BotBrain
	brain.seed_randomness(5, 1)
	brain._draw_personality()
	var first: Dictionary = _fields(brain.config)
	assert_ne(first, _fields(BotDifficulty.for_tier(brain.difficulty)), "a personality")
	brain._draw_personality()
	assert_eq(_fields(brain.config), first, "and only one")


# ─── SAMPLING ────────────────────────────────────────────────────────────────


func test_zero_temperature_is_the_argmax() -> void:
	assert_eq(BotSampling.pick([1.0, 3.0, 2.0], 0.0, _rng(1)), 1)
	assert_eq(BotSampling.pick([1.0, 3.0, 2.0], 0.5, null), 1, "no generator is an argmax too")
	assert_eq(BotSampling.order([1.0, 3.0, 2.0], 0.0, _rng(1)), [1, 2, 0] as Array[int])
	assert_eq(BotSampling.pick([], 0.5, _rng(1)), -1)


func test_a_temperature_sometimes_takes_the_runner_up_and_never_a_hopeless_one() -> void:
	var rng := _rng(9)
	var counts: Array[int] = [0, 0, 0]
	for i: int in 400:
		counts[BotSampling.pick([100.0, 95.0, 1.0], 0.1, rng)] += 1
	assert_gt(counts[0], counts[1], "the best is still the usual choice")
	assert_gt(counts[1], 20, "a near-best option is taken sometimes")
	assert_eq(counts[2], 0, "an option 99% worse at temperature 0.1 is never taken")


func test_sampling_reproduces_from_the_seed() -> void:
	var a: Array[int] = []
	var b: Array[int] = []
	var rng_a := _rng(77)
	var rng_b := _rng(77)
	for i: int in 50:
		a.append(BotSampling.pick([10.0, 9.0, 8.0], 0.3, rng_a))
		b.append(BotSampling.pick([10.0, 9.0, 8.0], 0.3, rng_b))
	assert_eq(a, b)


func test_non_positive_scores_fall_back_to_the_argmax() -> void:
	assert_eq(BotSampling.pick([0.0, -1.0], 0.5, _rng(1)), 0)


## Every parity the search can draw leaves a bot able to attack: its value ratio is at most
## 1 / parity once the humility prior binds, and the stalemate clock relaxes the bar no lower
## than MIN_ATTACK_RATIO. A parity past 1 / MIN_ATTACK_RATIO never attacks at all.
func test_no_searchable_parity_forbids_attacking() -> void:
	var highest: float = float(BotDifficulty.SEARCH_RANGES["assumed_enemy_parity"][1])
	assert_gt(1.0 / highest, BotMilitary.MIN_ATTACK_RATIO)
	for tier: int in PlayerSlot.Difficulty.values():
		var parity: float = BotDifficulty.for_tier(tier).assumed_enemy_parity
		assert_lte(parity, highest, "tier %d is inside the range" % tier)
