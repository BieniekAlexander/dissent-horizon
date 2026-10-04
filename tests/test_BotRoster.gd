extends GutTest
## A scenario names a trained personality by roster id; the vector lands on top of the
## slot's tier, and anything that cannot resolve is refused whole, at boot.

const RUSHER_VECTOR: Dictionary = {"army_commit_threshold": 1, "economy_reserve": 0}


func _fixture() -> BotRoster:
	return BotRoster.from_dictionary(
		{"members": {"rusher": {"tier": "HARD", "vector": RUSHER_VECTOR}}}
	)


func _slot(a_personality: String, a_overrides: Dictionary = {}) -> PlayerSlot:
	var slot := PlayerSlot.new()
	slot.difficulty = PlayerSlot.Difficulty.HARD
	slot.personality = a_personality
	slot.config_overrides = a_overrides
	return slot


func _scenario() -> Scenario:
	var scenario := Scenario.new()
	scenario._loaded_bot_roster = _fixture()
	return scenario


func test_a_roster_lists_its_members() -> void:
	var roster: BotRoster = _fixture()
	assert_true(roster.has("rusher"))
	assert_false(roster.has("nobody"))
	assert_eq(roster.ids(), ["rusher"] as Array[String])
	assert_eq(roster.trained_tier("rusher"), "HARD")


func test_a_members_vector_lands_on_top_of_the_tier() -> void:
	var config: BotDifficulty = BotDifficulty.for_tier(PlayerSlot.Difficulty.EASY)
	var easy_period: float = config.combat_period_seconds
	assert_eq(_fixture().apply("rusher", config), "")
	assert_eq(config.army_commit_threshold, 1)
	assert_eq(config.economy_reserve, 0)
	assert_eq(config.combat_period_seconds, easy_period, "the tier keeps the periods")


func test_an_unknown_member_is_refused_and_the_config_untouched() -> void:
	var config: BotDifficulty = BotDifficulty.for_tier(PlayerSlot.Difficulty.HARD)
	var before: int = config.army_commit_threshold
	assert_ne(_fixture().apply("nobody", config), "")
	assert_eq(config.army_commit_threshold, before)


func test_overrides_coerce_json_numbers_to_the_fields_own_type() -> void:
	var config := BotDifficulty.new()
	assert_eq(config.apply_overrides({"army_commit_threshold": 7.0, "may_attack": 0}), "")
	assert_eq(config.army_commit_threshold, 7)
	assert_true(typeof(config.army_commit_threshold) == TYPE_INT)
	assert_false(config.may_attack)


func test_an_unknown_field_refuses_the_whole_dictionary() -> void:
	var config := BotDifficulty.new()
	var before: int = config.army_commit_threshold
	var error: String = config.apply_overrides({"army_commit_threshold": 9, "no_such_field": 1})
	assert_string_contains(error, "no_such_field")
	assert_eq(config.army_commit_threshold, before, "nothing applied")


func test_a_missing_roster_file_is_an_empty_roster() -> void:
	var roster: BotRoster = BotRoster.load_from("user://no_such_roster.json")
	assert_eq(roster.ids().size(), 0)


func test_a_slot_naming_nobody_keeps_the_tiers_own_config() -> void:
	var scenario: Scenario = _scenario()
	assert_null(scenario._personality_config(_slot("")))
	assert_eq(scenario._unresolved_personality_slots(), {})
	scenario.free()


func test_a_named_personality_resolves_to_the_tier_plus_its_vector() -> void:
	var scenario: Scenario = _scenario()
	var config: BotDifficulty = scenario._personality_config(
		_slot("rusher", {"scout_unit_budget": 0})
	)
	assert_eq(config.army_commit_threshold, 1, "from the roster")
	assert_eq(config.scout_unit_budget, 0, "from the slot's overrides")
	assert_eq(
		config.combat_period_seconds,
		BotDifficulty.for_tier(PlayerSlot.Difficulty.HARD).combat_period_seconds,
		"from the tier"
	)
	scenario.free()


func test_unresolved_slots_are_reported_by_commander_id() -> void:
	var scenario: Scenario = _scenario()
	scenario.player_slots = [_slot("rusher"), _slot("nobody"), _slot("", {"typo": 1})]
	var unresolved: Dictionary = scenario._unresolved_personality_slots()
	assert_eq(unresolved.keys(), [2, 3])
	assert_string_contains(unresolved[2], "nobody")
	assert_string_contains(unresolved[3], "typo")
	scenario.free()
