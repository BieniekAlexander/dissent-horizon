extends GutTest

## The mission's difficulty: one dial the player picks on the Campaign page, which is every bot
## slot's tier AND the `difficulty` a scenario expression reads; and ConditionExpression, which
## lets an expression gate a whole trigger or tactic rule.
## gdd/systems/scenario-scripting/tactics.md §Trigger-decided mission commanders.

const MENU_SCENE := "res://scenes/menu/main_menu.tscn"

var _scenario: Scenario
var _manager: ScenarioTriggerManager


func before_each() -> void:
	_scenario = Scenario.new()
	_scenario.tick = 0
	_manager = ScenarioTriggerManager.new()
	add_child_autofree(_manager)
	assert_push_warning("expected parent to be Scenario")
	_manager.scenario = _scenario


func after_each() -> void:
	if _manager != null and _manager.simulation_clock != null:
		_manager.simulation_clock.clear()
	if _scenario != null:
		_scenario.free()


func _slot(a_is_bot: bool, a_tier: PlayerSlot.Difficulty) -> PlayerSlot:
	var slot := PlayerSlot.new()
	slot.is_bot = a_is_bot
	slot.difficulty = a_tier
	return slot


#region Slot tiers
func test_the_mission_difficulty_never_changes_a_slots_tier() -> void:
	# A mission is made harder by triggers authored against `difficulty`, never by its bots.
	var slot: PlayerSlot = _slot(true, PlayerSlot.Difficulty.PASSIVE)
	_scenario.mission_difficulty = Scenario.MissionDifficulty.HARD
	_scenario.player_slots = [slot] as Array[PlayerSlot]
	var header: Dictionary = ReplayFile.header_for(_scenario, "test")
	assert_eq(int((header["slots"] as Array)[0]["difficulty"]), int(PlayerSlot.Difficulty.PASSIVE))
	assert_eq(slot.difficulty, PlayerSlot.Difficulty.PASSIVE)


func test_only_easy_medium_and_hard_exist() -> void:
	assert_eq(Scenario.MissionDifficulty.keys(), ["EASY", "MEDIUM", "HARD"])
	assert_eq(Scenario.MissionDifficulty.values(), [1, 2, 3], "what expressions compare against")


#endregion


#region The expression input
func test_difficulty_reads_the_mission_difficulty() -> void:
	_scenario.mission_difficulty = Scenario.MissionDifficulty.EASY
	assert_eq(ScenarioExpression.evaluate_int("difficulty", 0, _manager), 1)
	_scenario.mission_difficulty = Scenario.MissionDifficulty.HARD
	assert_eq(ScenarioExpression.evaluate_int("4 + 2 * difficulty", 0, _manager), 10)


func test_a_scenario_nobody_picked_for_reads_medium() -> void:
	assert_eq(ScenarioExpression.evaluate_int("difficulty", 0, _manager), 2)


func test_difficulty_validates_as_a_known_name() -> void:
	assert_eq(ScenarioExpression.validation_error("difficulty * 2"), "")


func test_a_truth_validates_only_where_one_is_allowed() -> void:
	assert_eq(ScenarioExpression.validation_error("difficulty >= 2", true), "")
	assert_ne(ScenarioExpression.validation_error("difficulty >= 2"), "", "a number field")


func test_evaluate_bool_takes_comparisons_and_numbers() -> void:
	_scenario.mission_difficulty = Scenario.MissionDifficulty.MEDIUM
	assert_true(ScenarioExpression.evaluate_bool("difficulty >= 2", false, _manager))
	assert_false(ScenarioExpression.evaluate_bool("difficulty == 3", true, _manager))
	assert_true(ScenarioExpression.evaluate_bool("difficulty - 1", false, _manager), "nonzero")
	assert_false(ScenarioExpression.evaluate_bool("difficulty - 2", true, _manager), "zero")


func test_evaluate_bool_falls_back_on_a_bad_name() -> void:
	assert_true(ScenarioExpression.evaluate_bool("dificulty > 1", true, _manager))
	assert_push_warning("could not evaluate")


#endregion


#region ConditionExpression
func test_condition_expression_follows_its_expression() -> void:
	var condition := ConditionExpression.new()
	condition.expression = "difficulty >= 2"
	_scenario.mission_difficulty = Scenario.MissionDifficulty.EASY
	assert_false(condition.evaluate(_manager), "EASY is gated out")
	_scenario.mission_difficulty = Scenario.MissionDifficulty.HARD
	assert_true(condition.evaluate(_manager), "HARD is let in")


func test_a_blank_condition_expression_is_false_and_warned() -> void:
	var condition := ConditionExpression.new()
	assert_false(condition.evaluate(_manager))
	assert_ne(condition.configuration_warning(), "", "the Scene dock says why")


func test_a_broken_condition_expression_is_warned() -> void:
	var condition := ConditionExpression.new()
	condition.expression = "dificulty >= 2"
	assert_string_contains(condition.configuration_warning(), "dificulty")


#endregion


#region Replay and menu
func test_the_replay_header_records_the_mission_difficulty() -> void:
	_scenario.mission_difficulty = Scenario.MissionDifficulty.HARD
	_scenario.player_slots = [_slot(true, PlayerSlot.Difficulty.EASY)] as Array[PlayerSlot]
	var header: Dictionary = ReplayFile.header_for(_scenario, "test")
	assert_eq(int(header["mission_difficulty"]), int(Scenario.MissionDifficulty.HARD))


func test_the_campaign_page_offers_three_difficulties_at_medium() -> void:
	var menu: MainMenu = load(MENU_SCENE).instantiate() as MainMenu
	menu.scenarios = [] as Array[ScenarioEntry]
	add_child_autofree(menu)
	assert_push_warning("no scenarios authored")
	var picker: OptionButton = menu.difficulty_control()
	assert_eq(picker.item_count, 3)
	assert_eq(menu.campaign_difficulty, Scenario.MissionDifficulty.MEDIUM)
	assert_eq(picker.get_selected_id(), int(Scenario.MissionDifficulty.MEDIUM))
	picker.select(picker.get_item_index(Scenario.MissionDifficulty.HARD))
	picker.item_selected.emit(picker.selected)
	assert_eq(menu.campaign_difficulty, Scenario.MissionDifficulty.HARD)

#endregion
