extends GutTest

## A scenario playing a recording back is watched, not played: it has the replay viewer, its
## player's HUD is for looking, and every session opens on its own player's view whatever the
## last one left behind. gdd/systems/commands/recording-and-replay.md §Watching.
##
## The scenario is a HARNESS — one human slot on a flat map — and its content does not matter.

const HARNESS: String = "res://scenes/scenarios/test/nav_straight_line.tscn"

var _saved_view: int


func before_each() -> void:
	_saved_view = Fog.active_commander_id


func after_each() -> void:
	Fog.active_commander_id = _saved_view
	PlaybackSpeed.reset()


func test_a_live_match_has_no_viewer_and_a_hud_for_playing() -> void:
	var scenario: Scenario = await _boot(null)
	assert_false(scenario.is_playback())
	assert_null(scenario.get_node_or_null("ReplayViewer"))
	assert_false(_controller(scenario).is_look_only)
	await _tear_down(scenario)


func test_a_playback_is_watched_through_the_viewer_with_a_hud_for_looking() -> void:
	var recording: ReplayFile = await _record()
	var scenario: Scenario = await _boot(recording)
	assert_true(scenario.is_playback())
	assert_true(scenario.order_stream.is_playback())
	assert_not_null(scenario.get_node_or_null("ReplayViewer"), "the replay keys and banner")
	var controller: RTSController = _controller(scenario)
	assert_true(controller.is_look_only)
	controller._update_selection_owned_panels()
	assert_false(
		(controller.get_node("CommandsSection") as Control).visible, "the command grid is hidden"
	)
	await _tear_down(scenario)


func test_a_session_opens_on_its_own_players_view() -> void:
	Fog.active_commander_id = ReplayViewer.VIEW_EVERYTHING
	var scenario: Scenario = await _boot(null)
	assert_eq(Fog.active_commander_id, -1, "a previous session's view does not carry over")
	await _tear_down(scenario)


func test_the_header_records_each_slot_and_its_start_point() -> void:
	var scenario: Scenario = await _boot(null)
	var slots: Array = scenario.recorder.replay.header.get("slots", [])
	assert_eq(slots.size(), 1)
	assert_eq(slots[0].get("start_point"), {}, "a scenario that places by authoring has none")
	await _tear_down(scenario)


func _record() -> ReplayFile:
	var scenario: Scenario = await _boot(null)
	for i: int in 10:
		await get_tree().physics_frame
	var recording: ReplayFile = scenario.recorder.replay
	await _tear_down(scenario)
	return ReplayFile.from_bytes(recording.to_bytes())


func _boot(a_recording: ReplayFile) -> Scenario:
	gut.error_tracker.disabled = true
	var scenario := (load(HARNESS) as PackedScene).instantiate() as Scenario
	scenario.replay_to_play = a_recording
	await get_tree().process_frame
	add_child(scenario)
	await get_tree().process_frame
	return scenario


func _tear_down(a_scenario: Scenario) -> void:
	a_scenario.free()
	await get_tree().process_frame
	gut.error_tracker.disabled = false


func _controller(a_scenario: Scenario) -> RTSController:
	return a_scenario.local_player().get_node("Controller") as RTSController
