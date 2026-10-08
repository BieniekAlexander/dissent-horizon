extends GutTest

## The statistics a summary reads off an event log — pure functions of the events, here a
## synthetic log in the shape MatchLog writes.


func _log() -> Array:
	return [
		{"type": MatchLog.MATCH_STARTED, "commanders": [{"id": 1}, {"id": 2}]},
		{
			"type": MatchLog.PURCHASE_FUNDED,
			"commander": 1,
			"kind": MatchLog.KIND_UNIT,
			"piece": "rifle"
		},
		{
			"type": MatchLog.PURCHASE_COMPLETED,
			"commander": 1,
			"kind": MatchLog.KIND_UNIT,
			"piece": "rifle"
		},
		{
			"type": MatchLog.PURCHASE_COMPLETED,
			"commander": 1,
			"kind": MatchLog.KIND_UNIT,
			"piece": "tank"
		},
		{
			"type": MatchLog.PURCHASE_COMPLETED,
			"commander": 1,
			"kind": MatchLog.KIND_STRUCTURE,
			"piece": "depot"
		},
		{
			"type": MatchLog.PURCHASE_COMPLETED,
			"commander": 1,
			"kind": MatchLog.KIND_UPGRADE,
			"piece": "drill"
		},
		{"type": MatchLog.CONSTRUCTION_FINISHED, "commander": 1, "piece": "depot"},
		{"type": MatchLog.MATCH_ENDED, "winner": 1},
	]


func test_units_are_completed_purchases_and_structures_are_finished_constructions() -> void:
	var counts: Dictionary = MatchSummary.created_counts(_log())
	assert_eq(counts[1], {"units": 2, "structures": 1}, "a laid foundation is not yet built")


func test_the_breakdown_counts_each_piece_made() -> void:
	var made: Dictionary = MatchSummary.created_by_piece(_log())
	assert_eq(made[1], {"units": {"rifle": 1, "tank": 1}, "structures": {"depot": 1}})
	assert_eq(made[2], {"units": {}, "structures": {}})


func test_a_commander_that_made_nothing_is_listed_at_zero() -> void:
	assert_eq(MatchSummary.created_counts(_log())[2], {"units": 0, "structures": 0})


func test_the_winner_is_read_off_the_end() -> void:
	assert_eq(MatchSummary.winner(_log()), 1)
	assert_eq(MatchSummary.winner(_log().slice(0, -1)), -1, "a running match has none")


func test_a_log_read_back_from_json_counts_the_same() -> void:
	var text: String = "".join(
		_log().map(func(e: Dictionary) -> String: return JSON.stringify(e) + "\n")
	)
	var parsed: Array[Dictionary] = MatchLog.parse_jsonl(text)
	assert_eq(MatchSummary.created_counts(parsed), MatchSummary.created_counts(_log()))
	assert_eq(MatchSummary.commander_ids(parsed), [1, 2])
