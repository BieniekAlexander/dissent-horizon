extends GutTest
## The ledger the piece-usage audit reads: what the bot considered, chose, ordered and was
## refused, counted per piece, and a summary a JSON writer takes as is.


func test_a_choice_counts_every_candidate_and_credits_the_winner() -> void:
	var log := BotUsageLog.new()
	log.record_choice("train", {&"a": 1.0, &"b": 3.0}, &"b")
	log.record_choice("train", {&"a": 2.0, &"b": 1.0}, &"a")
	var rows: Dictionary = log.choices()["train"]
	assert_eq(rows["a"]["considered"], 2)
	assert_eq(rows["a"]["chosen"], 1)
	assert_eq(rows["b"]["chosen"], 1)
	assert_almost_eq(rows["a"]["score_sum"], 3.0, 0.001)
	assert_almost_eq(rows["a"]["best_sum"], 5.0, 0.001, "the winner's score, both times")


func test_a_choice_that_took_nothing_still_counts_the_candidates() -> void:
	var log := BotUsageLog.new()
	log.record_choice("train", {&"a": 0.0}, &"")
	assert_eq(log.choices()["train"]["a"]["considered"], 1)
	assert_eq(log.choices()["train"]["a"]["chosen"], 0)


func test_actions_count_by_kind_piece_and_outcome() -> void:
	var log := BotUsageLog.new()
	log.record_action("build", &"tower", BotUsageLog.OUTCOME_ISSUED)
	log.record_action("build", &"tower", BotUsageLog.OUTCOME_ISSUED)
	log.record_action(
		"build",
		&"tower",
		BotUsageLog.refused(MoveCommand.PreconditionFailureCause.MISSING_STRUCTURE)
	)
	var row: Dictionary = log.actions()["build"]["tower"]
	assert_eq(row[BotUsageLog.OUTCOME_ISSUED], 2)
	assert_eq(row["refused:MISSING_STRUCTURE"], 1, "the cause is named, not numbered")


func test_cast_positions_are_kept_per_ability_on_the_ground_plane() -> void:
	var log := BotUsageLog.new()
	log.record_cast_position(&"scan", Vector3(1.0, 9.0, 2.0))
	log.record_cast_position(&"scan", Vector3(1.0, 0.0, 2.0))
	assert_eq(log.summary()["cast_positions"]["scan"], [[1.0, 2.0], [1.0, 2.0]])


func test_the_summary_is_plain_data_and_a_copy() -> void:
	var log := BotUsageLog.new()
	log.record_action("train", &"recruit", BotUsageLog.OUTCOME_ISSUED)
	var summary: Dictionary = log.summary()
	assert_ne(JSON.stringify(summary), "", "serialises")
	summary["actions"]["train"]["recruit"][BotUsageLog.OUTCOME_ISSUED] = 99
	assert_eq(log.actions()["train"]["recruit"][BotUsageLog.OUTCOME_ISSUED], 1)


func test_the_latest_choices_keep_the_winner_and_its_runner_up() -> void:
	var log := BotUsageLog.new()
	log.record_choice("train", {&"recruit": 0.4, &"tank": 0.9, &"drone": 0.6}, &"tank")
	var recent: Array[Dictionary] = log.recent_choices()
	assert_eq(recent.size(), 1)
	assert_eq(recent[0]["chosen"], "tank")
	assert_almost_eq(recent[0]["chosen_score"], 0.9, 1e-5)
	assert_eq(recent[0]["runner_up"], "drone")
	assert_almost_eq(recent[0]["runner_up_score"], 0.6, 1e-5)


func test_only_the_latest_choices_are_kept() -> void:
	var log := BotUsageLog.new()
	for i: int in BotUsageLog.RECENT_CHOICE_COUNT + 3:
		log.record_choice("train", {&"only": float(i)}, &"only")
	var recent: Array[Dictionary] = log.recent_choices()
	assert_eq(recent.size(), BotUsageLog.RECENT_CHOICE_COUNT)
	assert_almost_eq(recent[-1]["chosen_score"], float(BotUsageLog.RECENT_CHOICE_COUNT + 2), 1e-5)
	assert_eq(recent[-1]["runner_up"], "", "a lone candidate has no runner-up")
