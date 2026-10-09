extends GutTest

## The keys a playback is watched through: pause, slower, faster, switch view — and that none of
## them reaches the simulation's own notion of who the player is.
## gdd/systems/commands/recording-and-replay.md §Watching.

var _saved_view: int
var _saved_player: int


func before_each() -> void:
	_saved_view = Fog.active_commander_id
	_saved_player = RTSController.PLAYER_COMMANDER_ID


func after_each() -> void:
	Fog.active_commander_id = _saved_view
	RTSController.PLAYER_COMMANDER_ID = _saved_player
	PlaybackSpeed.reset()


func test_the_replay_keys_exist() -> void:
	for action: StringName in [
		ReplayViewer.ACTION_PAUSE,
		ReplayViewer.ACTION_SLOWER,
		ReplayViewer.ACTION_FASTER,
		ReplayViewer.ACTION_SWITCH_VIEW,
	]:
		assert_true(InputMap.has_action(action), "%s is bound" % action)
		assert_false(
			String(action).begins_with("command_"), "%s stays out of the grid dispatcher" % action
		)


func test_speed_steps_along_the_ladder_and_holds_at_its_ends() -> void:
	assert_eq(ReplayViewer.next_speed(1.0, 1), 2.0)
	assert_eq(ReplayViewer.next_speed(1.0, -1), 0.5)
	assert_eq(ReplayViewer.next_speed(4.0, 1), 4.0, "held at the top")
	assert_eq(ReplayViewer.next_speed(0.25, -1), 0.25, "held at the bottom")
	assert_eq(ReplayViewer.next_speed(0.27, 1), 0.5, "a quantised speed steps from its nearest")


func test_every_ladder_speed_is_one_playback_speed_allows() -> void:
	for speed: float in ReplayViewer.SPEEDS:
		assert_between(speed, PlaybackSpeed.MIN_MULTIPLIER, PlaybackSpeed.MAX_MULTIPLIER)


func test_the_view_cycles_through_each_commander() -> void:
	var views: Array[int] = [1, 2, 3]
	assert_eq(ReplayViewer.next_view(views, 1), 2)
	assert_eq(ReplayViewer.next_view(views, 3), 1, "round again")
	assert_eq(ReplayViewer.next_view(views, 7), 1, "an unknown view starts at the first")
	assert_eq(ReplayViewer.next_view([] as Array[int], 2), 2, "no views: the view stays")


func test_pausing_is_the_playback_pause_hold() -> void:
	var clock := SimulationClock.new()
	var viewer: ReplayViewer = _viewer(clock)
	viewer.toggle_pause()
	assert_true(clock.is_held_by(SimulationClock.REASON_PLAYBACK_PAUSE))
	assert_true(viewer.is_paused())
	assert_string_contains(viewer.banner_text(), "paused")
	viewer.toggle_pause()
	assert_false(clock.is_paused())
	clock.free()


func test_switching_the_view_never_changes_the_local_player() -> void:
	RTSController.PLAYER_COMMANDER_ID = 1
	Fog.active_commander_id = -1
	var viewer: ReplayViewer = _viewer(null)
	assert_eq(viewer.current_view(), 1, "the default view is the local player's")
	viewer.switch_view()
	assert_eq(RTSController.PLAYER_COMMANDER_ID, 1, "the simulation's player is untouched")
	assert_string_contains(viewer.banner_text(), "Commander 1")


func test_the_banner_says_when_the_fog_is_lifted() -> void:
	RTSController.PLAYER_COMMANDER_ID = 1
	Fog.active_commander_id = -1
	var viewer: ReplayViewer = _viewer(null)
	assert_false(viewer.banner_text().contains("no fog"))
	Fog.set_view_lifted(true)
	assert_string_contains(viewer.banner_text(), "Commander 1, no fog")
	Fog.set_view_lifted(false)


func test_the_speed_keys_set_the_playback_speed() -> void:
	var viewer: ReplayViewer = _viewer(null)
	viewer.step_speed(1)
	assert_almost_eq(PlaybackSpeed.multiplier(), 2.0, 0.01)
	viewer.step_speed(-1)
	viewer.step_speed(-1)
	assert_almost_eq(PlaybackSpeed.multiplier(), 0.5, 0.05)


func _viewer(a_clock: SimulationClock) -> ReplayViewer:
	var viewer := ReplayViewer.new()
	add_child_autofree(viewer)
	viewer.bind(null, a_clock)
	return viewer
