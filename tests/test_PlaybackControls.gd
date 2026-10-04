extends GutTest

## The pause menu's playback section: shown only under `debug_allowed`, and its pause is a
## SimulationClock hold of its own that survives the menu closing.

const SCENE: String = "res://scenes/menu/pause_menu.tscn"

var _menu: PauseMenu
var _controls: PlaybackControls
var _clock: SimulationClock
var _was_allowed: bool


func before_each() -> void:
	_was_allowed = DebugMode.is_allowed()
	_menu = load(SCENE).instantiate() as PauseMenu
	add_child_autofree(_menu)
	_controls = _menu.find_child("PlaybackControls", true, false) as PlaybackControls
	# An ORPHAN clock, as in test_PauseMenu: bookkeeping without pausing GUT itself.
	_clock = SimulationClock.new()
	_menu._clock = _clock
	_controls.bind(_clock)


func after_each() -> void:
	DebugMode.configure(_was_allowed)
	PlaybackSpeed.reset()
	_clock.clear()
	_clock.free()


func test_hidden_unless_the_session_allows_debug() -> void:
	DebugMode.configure(false)
	_menu.open()
	assert_false(_controls.visible)
	_menu.close()
	DebugMode.configure(true)
	_menu.open()
	assert_true(_controls.visible)


func test_the_pause_outlives_the_menu() -> void:
	DebugMode.configure(true)
	_menu.open()
	(_controls.find_child("PauseToggle", true, false) as CheckButton).button_pressed = true
	_menu.close()
	assert_true(_clock.is_held_by(SimulationClock.REASON_PLAYBACK_PAUSE), "still held")
	_menu.open()
	(_controls.find_child("PauseToggle", true, false) as CheckButton).button_pressed = false
	assert_false(_clock.is_held_by(SimulationClock.REASON_PLAYBACK_PAUSE), "released")


func test_the_slider_sets_the_speed_and_max_speed_overrides_it() -> void:
	DebugMode.configure(true)
	_menu.open()
	var slider: HSlider = _controls.find_child("SpeedSlider", true, false) as HSlider
	slider.value = 2 * TimeUtils.ticks_per_second()
	assert_almost_eq(PlaybackSpeed.multiplier(), 2.0, 1e-6)
	(_controls.find_child("UncappedToggle", true, false) as CheckButton).button_pressed = true
	assert_true(PlaybackSpeed.is_uncapped())
	assert_false(slider.editable, "the slider is moot at max speed")
	(_controls.find_child("NormalButton", true, false) as Button).pressed.emit()
	assert_eq(PlaybackSpeed.multiplier(), PlaybackSpeed.NORMAL_MULTIPLIER)
