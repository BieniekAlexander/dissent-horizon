extends GutTest

## The playback controls: offered under `debug_allowed` and in every replay, and their pause is a
## SimulationClock hold of its own, so it composes with the pause menu's.

const SCENE: String = "res://scenes/interface/playback_controls.tscn"

var _controls: PlaybackControls
var _clock: SimulationClock
var _was_allowed: bool


func before_each() -> void:
	_was_allowed = DebugMode.is_allowed()
	_controls = load(SCENE).instantiate() as PlaybackControls
	add_child_autofree(_controls)
	# An ORPHAN clock, as in test_PauseMenu: bookkeeping without pausing GUT itself.
	_clock = SimulationClock.new()
	_controls.bind(_clock)


func after_each() -> void:
	DebugMode.configure(_was_allowed)
	PlaybackSpeed.reset()
	_clock.clear()
	_clock.free()


func test_offered_under_debug_or_in_a_replay() -> void:
	DebugMode.configure(false)
	assert_false(PlaybackControls.is_offered(false))
	assert_true(PlaybackControls.is_offered(true), "a replay's speed is the viewer's")
	DebugMode.configure(true)
	assert_true(PlaybackControls.is_offered(false))


func test_the_pause_is_its_own_hold() -> void:
	_clock.hold(SimulationClock.REASON_PAUSE_MENU)
	(_controls.find_child("PauseToggle", true, false) as CheckButton).button_pressed = true
	_clock.release(SimulationClock.REASON_PAUSE_MENU)
	assert_true(_clock.is_held_by(SimulationClock.REASON_PLAYBACK_PAUSE), "still held")
	(_controls.find_child("PauseToggle", true, false) as CheckButton).button_pressed = false
	assert_false(_clock.is_held_by(SimulationClock.REASON_PLAYBACK_PAUSE), "released")


func test_the_toggle_reads_a_pause_taken_elsewhere() -> void:
	_clock.hold(SimulationClock.REASON_PLAYBACK_PAUSE)
	_controls.refresh()
	assert_true((_controls.find_child("PauseToggle", true, false) as CheckButton).button_pressed)


func test_the_slider_sets_the_speed_and_max_speed_overrides_it() -> void:
	var slider: HSlider = _controls.find_child("SpeedSlider", true, false) as HSlider
	slider.value = 2 * TimeUtils.ticks_per_second()
	assert_almost_eq(PlaybackSpeed.multiplier(), 2.0, 1e-6)
	(_controls.find_child("UncappedToggle", true, false) as CheckButton).button_pressed = true
	assert_true(PlaybackSpeed.is_uncapped())
	assert_false(slider.editable, "the slider is moot at max speed")
	(_controls.find_child("NormalButton", true, false) as Button).pressed.emit()
	assert_eq(PlaybackSpeed.multiplier(), PlaybackSpeed.NORMAL_MULTIPLIER)
