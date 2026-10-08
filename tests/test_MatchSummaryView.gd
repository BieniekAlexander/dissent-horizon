extends GutTest

## The summary view draws what a log says and nothing else, and the pause menu offers it only
## while the debug view is up.


func after_each() -> void:
	DebugMode.configure(false)


func _events() -> Array:
	return [
		{"type": MatchLog.MATCH_STARTED, "commanders": [{"id": 1}, {"id": 2}]},
		{
			"type": MatchLog.PURCHASE_COMPLETED,
			"commander": 2,
			"kind": MatchLog.KIND_UNIT,
			"piece": "rifle"
		},
		{"type": MatchLog.CONSTRUCTION_FINISHED, "commander": 1, "piece": "depot"},
		{"type": MatchLog.MATCH_ENDED, "winner": 2},
	]


func test_it_tabulates_each_commanders_counts_and_marks_the_winner() -> void:
	var view: MatchSummaryView = load("res://scenes/interface/match_summary.tscn").instantiate()
	add_child_autofree(view)
	view.show_events(_events(), "Title")
	var expected: Array[String] = [
		"Commander",
		"Units trained",
		"Structures built",
		"Commander 1",
		"0",
		"1",
		"Commander 2  (winner)",
		"1",
		"0",
	]
	assert_eq(view.cell_texts(), expected)


func test_it_breaks_the_counts_down_by_piece_per_commander() -> void:
	var view: MatchSummaryView = load("res://scenes/interface/match_summary.tscn").instantiate()
	add_child_autofree(view)
	view.show_events(_events(), "Title")
	var expected: Array[String] = [
		"Units trained",
		"Commander 1",
		"Commander 2",
		"  rifle",
		"0",
		"1",
		"Structures built",
		"Commander 1",
		"Commander 2",
		"  depot",
		"1",
		"0",
	]
	assert_eq(view.breakdown_texts(), expected)


func test_a_section_nobody_made_anything_in_says_so() -> void:
	var view: MatchSummaryView = load("res://scenes/interface/match_summary.tscn").instantiate()
	add_child_autofree(view)
	view.show_events(_events().slice(0, 1), "Title")
	var expected: Array[String] = [
		"Units trained",
		"Commander 1",
		"Commander 2",
		"  none",
		"",
		"",
		"Structures built",
		"Commander 1",
		"Commander 2",
		"  none",
		"",
		"",
	]
	assert_eq(view.breakdown_texts(), expected)


func test_showing_again_replaces_the_table() -> void:
	var view: MatchSummaryView = load("res://scenes/interface/match_summary.tscn").instantiate()
	add_child_autofree(view)
	view.show_events(_events(), "Title")
	view.show_events(_events(), "Title")
	assert_eq(view.cell_texts().size(), 9)
	assert_eq(view.breakdown_texts().size(), 12)


func test_the_pause_menu_offers_the_summary_only_under_debug() -> void:
	var menu: PauseMenu = load("res://scenes/menu/pause_menu.tscn").instantiate()
	add_child_autofree(menu)
	var match_log := MatchLog.new()
	add_child_autofree(match_log)
	menu.bind_match_log(match_log)
	var summary: Control = menu.get_node("%MatchSummary")
	DebugMode.configure(true)
	menu.open()
	assert_false(summary.visible, "debug view down")
	menu.close()
	DebugMode.toggle()
	menu.open()
	assert_true(summary.visible, "debug view up")
	menu.close()
