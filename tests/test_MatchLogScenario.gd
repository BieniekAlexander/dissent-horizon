extends GutTest

## A scenario records its match: the header and resource samples as it runs, and its end once,
## with the summary shown whether or not the debug view is up.

const SCENE: String = "res://scenes/scenarios/test/test_scout_coverage.tscn"
## Physics frames past the first resource sample.
const RUN_FRAMES: int = 200

var _scenario: Scenario


func before_all() -> void:
	gut.error_tracker.disabled = true  # mute Godot 4.7 navmesh bring-up engine noise


func after_all() -> void:
	gut.error_tracker.disabled = false


func _boot() -> void:
	_scenario = (load(SCENE) as PackedScene).instantiate()
	add_child_autofree(_scenario)
	for _i: int in RUN_FRAMES:
		await get_tree().physics_frame


func _of_type(a_type: String) -> Array:
	return _scenario.match_log.events.filter(
		func(e: Dictionary) -> bool: return e["type"] == a_type
	)


func test_a_running_match_has_a_header_and_resource_samples() -> void:
	await _boot()
	assert_eq(_scenario.match_log.events[0]["type"], MatchLog.MATCH_STARTED)
	assert_gt(_of_type(MatchLog.STATS).size(), 1, "sampled on its period")
	assert_true(_of_type(MatchLog.STATS)[0].has("army_value"))


func test_ending_the_match_records_it_once_and_shows_the_summary() -> void:
	await _boot()
	DebugMode.configure(false)
	_scenario.end_match(1)
	_scenario.end_match(2)
	var ended: Array = _of_type(MatchLog.MATCH_ENDED)
	assert_eq(ended.size(), 1)
	assert_eq(ended[0]["winner"], 1)
	assert_not_null(_scenario.get_node_or_null("MatchSummaryLayer"), "shown without debug")
