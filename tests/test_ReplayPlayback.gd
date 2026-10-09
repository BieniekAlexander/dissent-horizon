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


func test_a_live_match_has_no_viewer_and_the_players_rig() -> void:
	var scenario: Scenario = await _boot(null)
	assert_false(scenario.is_playback())
	assert_null(scenario.get_node_or_null("ReplayViewer"))
	assert_not_null(scenario.local_player().get_node_or_null("Controller"), "the player's HUD")
	assert_null(scenario.get_node_or_null("SpectatorHUD"))
	await _tear_down(scenario)


func test_a_playback_is_a_spectator_session_with_the_viewer_on_top() -> void:
	var recording: ReplayFile = await _record()
	var scenario: Scenario = await _boot(recording)
	assert_true(scenario.is_playback())
	assert_true(scenario.order_stream.is_playback())
	assert_not_null(scenario.get_node_or_null("ReplayViewer"), "the replay keys and banner")
	assert_not_null(scenario.get_node_or_null("SpectatorHUD"), "the spectator's HUD")
	assert_not_null(scenario.get_node_or_null("SpectatorCamera"), "the spectator's camera")
	assert_null(
		scenario.local_player().get_node_or_null("Controller"), "no player HUD to play with"
	)
	assert_eq(scenario.local_player().id, 1, "the recorded human is still the simulation's player")
	assert_eq(Fog.active_commander_id, 1, "watched from the recorded player's view first")
	await _tear_down(scenario)


func test_a_playback_has_the_look_only_hud_with_the_spectator_panel_in_the_grids_place() -> void:
	var recording: ReplayFile = await _record()
	var scenario: Scenario = await _boot(recording)
	var hud: RTSController = scenario.get_node_or_null("LookOnlyHUD") as RTSController
	assert_not_null(hud, "the player's HUD scene, look-only")
	assert_true(hud.is_look_only)
	assert_null(hud._commander(), "it drives no commander")
	hud._update_selection_owned_panels()
	assert_false((hud.get_node("CommandsSection") as Control).visible, "no command grid")
	assert_false((hud.get_node("EnergyBar") as Control).visible, "no commander's means")
	assert_true((hud.get_node("MapSection") as Control).visible, "the minimap stays")
	var panel: SpectatorPanel = hud.get_node("SpectatorPanel") as SpectatorPanel
	var slot: Control = hud.get_node("CommandsSection") as Control
	assert_eq(panel.offset_right, slot.offset_right, "in the command grid's slot")
	assert_eq(panel.offset_top, slot.offset_top)
	assert_eq(
		panel.button_labels(),
		["No fog", "Player 1", "Pause", "Slower", "Faster"] as Array[String],
		"the views, then the replay controls"
	)
	panel.show_view(SpectatorPanel.VIEW_EVERYTHING)
	assert_eq(Fog.active_commander_id, SpectatorPanel.VIEW_EVERYTHING)
	await _tear_down(scenario)


## Multiple selection is only ever of the user's own pieces, and a watcher owns none — not even
## the recorded player's, though that player is still the simulation's local player.
func test_a_watcher_selects_every_piece_as_a_player_selects_an_enemys() -> void:
	var live: Scenario = await _boot(null)
	var own: Actor = _piece_of(live.local_player())
	assert_true(_controller(live)._selects_as_own(own), "the player's own piece, live")
	await _tear_down(live)
	var recording: ReplayFile = await _record()
	var scenario: Scenario = await _boot(recording)
	var recorded: Actor = _piece_of(scenario.local_player())
	var hud: RTSController = scenario.get_node("LookOnlyHUD") as RTSController
	assert_false(hud._selects_as_own(recorded), "the recorded player's piece is not the watcher's")
	DebugMode.configure(true)
	DebugMode.toggle()
	assert_true(DebugMode.is_active())
	assert_false(hud._selects_as_own(recorded), "nor under the debug view")
	DebugMode.configure(false)
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


## A bare unit owned by `a_commander`, in its scenario's tree.
func _piece_of(a_commander: Commander) -> Actor:
	var piece: Actor = FakePieces.unit()
	a_commander.add_child(piece)
	piece.commander = a_commander
	return piece


func _controller(a_scenario: Scenario) -> RTSController:
	return a_scenario.local_player().get_node("Controller") as RTSController
