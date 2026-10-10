class_name PlaybackControls
extends VBoxContainer

## The pause menu's debug playback section: a speed slider, a pause toggle that outlives the
## menu, and "as fast as possible". Shown while the scenario has `debug_allowed`, and in every
## replay playback, where speed is the viewer's to set. The mechanism is PlaybackSpeed; this is
## only its controls. Layout is authored in scenes/interface/playback_controls.tscn.
##
## The slider takes no keyboard focus (`focus_mode` none in the scene): the arrow keys pan the
## camera, which works behind the menu, and a focused slider would take each press as a step —
## moving the speed while the player meant to look around.

@onready var _speed_slider: HSlider = %SpeedSlider
@onready var _speed_label: Label = %SpeedLabel
@onready var _pause_toggle: CheckButton = %PauseToggle
@onready var _uncapped_toggle: CheckButton = %UncappedToggle
@onready var _normal_button: Button = %NormalButton

## The scenario's clock, which the pause toggle holds. Null in a scene with no trigger manager,
## and the toggle is then disabled.
var _clock: SimulationClock = null
## Whether the scenario plays a recording back: the controls are offered whatever debug allows.
var _is_playback: bool = false


func _ready() -> void:
	var base: int = TimeUtils.ticks_per_second()
	# In engine ticks a second, so every slider stop is a rate the engine can actually run.
	_speed_slider.min_value = PlaybackSpeed.min_engine_ticks(base)
	_speed_slider.max_value = PlaybackSpeed.max_engine_ticks(base)
	_speed_slider.value_changed.connect(_on_speed_changed)
	_pause_toggle.toggled.connect(_on_pause_toggled)
	_uncapped_toggle.toggled.connect(_on_uncapped_toggled)
	_normal_button.pressed.connect(_on_normal_pressed)
	refresh()


func bind(a_clock: SimulationClock, a_is_playback: bool = false) -> void:
	_clock = a_clock
	_is_playback = a_is_playback
	refresh()


## Read the controls back from the live state, which may have changed since they were last up.
func refresh() -> void:
	visible = DebugMode.is_allowed() or _is_playback
	_uncapped_toggle.set_pressed_no_signal(PlaybackSpeed.is_uncapped())
	if not PlaybackSpeed.is_uncapped():
		_speed_slider.set_value_no_signal(PlaybackSpeed.multiplier() * TimeUtils.ticks_per_second())
	_speed_slider.editable = not PlaybackSpeed.is_uncapped()
	_pause_toggle.disabled = _clock == null
	_pause_toggle.set_pressed_no_signal(
		_clock != null and _clock.is_held_by(SimulationClock.REASON_PLAYBACK_PAUSE)
	)
	_speed_label.text = PlaybackSpeed.label_for(
		PlaybackSpeed.multiplier(), PlaybackSpeed.is_uncapped()
	)


func _on_speed_changed(a_engine_ticks: float) -> void:
	PlaybackSpeed.set_multiplier(a_engine_ticks / TimeUtils.ticks_per_second())
	refresh()


func _on_pause_toggled(a_is_paused: bool) -> void:
	if _clock == null or a_is_paused == _clock.is_held_by(SimulationClock.REASON_PLAYBACK_PAUSE):
		return
	if a_is_paused:
		_clock.hold(SimulationClock.REASON_PLAYBACK_PAUSE)
	else:
		_clock.release(SimulationClock.REASON_PLAYBACK_PAUSE)
	refresh()


func _on_uncapped_toggled(a_is_uncapped: bool) -> void:
	if a_is_uncapped:
		PlaybackSpeed.set_uncapped()
	else:
		PlaybackSpeed.set_multiplier(_speed_slider.value / TimeUtils.ticks_per_second())
	refresh()


func _on_normal_pressed() -> void:
	PlaybackSpeed.reset()
	refresh()
