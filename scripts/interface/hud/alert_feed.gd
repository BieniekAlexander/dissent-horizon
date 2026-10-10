class_name AlertFeed
extends VBoxContainer
## THE PLAYER'S ALERTS ON SCREEN: a short stack of toasts down the left edge, a sound per alert,
## and the memory behind the jump key. Built in code by RTSController, like CursorReadout.
##
## It shows what AlertCenter PRESENTS to whoever this HUD is showing — the local player, or in a
## spectator session or replay the commander being watched (alerts follow the perspective). A
## toast that may say where is clickable and jumps the camera there; one that may not
## (an enemy superweapon) is plain text, and the jump key skips it.
## gdd/systems/ux/ui/alerts.md §Presentation.

#region Signals
## A toast was clicked, or the jump key pressed: show the player `a_world_xz`.
signal jump_requested(a_world_xz: Vector2)
#endregion

#region Constants
const MAX_TOASTS: int = 5
## Real seconds a toast stays up, the last FADE_SECONDS of them fading.
const TOAST_SECONDS: float = 7.0
const FADE_SECONDS: float = 1.0
## The shortest real gap between two alert sounds. A louder alert interrupts a quieter one
## anyway; an equal or quieter one inside the gap stays silent (its toast still shows).
const SOUND_GAP_SECONDS: float = 1.0
## How many located alerts are remembered for the jump key to cycle back through.
const HISTORY_SIZE: int = 8
const HISTORY_DEPTH_FACTOR: int = 4
## A jump-key press this long after the last one starts again from the newest alert.
const JUMP_CYCLE_RESET_SECONDS: float = 3.0

const WIDTH: float = 300.0

## Clips by AlertCatalog.sound_of name: one per tone, plus the generic completion.
const SOUNDS: Dictionary = {
	&"routine": preload("res://assets/audio/alerts/alert_routine.wav"),
	&"warning": preload("res://assets/audio/alerts/alert_warning.wav"),
	&"urgent": preload("res://assets/audio/alerts/alert_urgent.wav"),
	&"complete": preload("res://assets/audio/alerts/alert_complete.wav"),
}
## A completion's own clip, by the piece id it bought (Alert.purchase), over the generic one.
## PLANNED: empty until purchases have sounds of their own — gdd/systems/ux/ui/alerts.md
## §Presentation.
const PURCHASE_SOUNDS: Dictionary = {}
const ACCENTS: Dictionary = {
	AlertCatalog.Tone.ROUTINE: Color(0.55, 0.75, 0.95),
	AlertCatalog.Tone.WARNING: Color(1.0, 0.75, 0.25),
	AlertCatalog.Tone.URGENT: Color(1.0, 0.3, 0.25),
}
#endregion

#region Properties
## Which commander's alerts to show. RTSController supplies the HUD's own perspective.
var viewer: Callable = func() -> int: return RTSController.PLAYER_COMMANDER_ID

var _center: AlertCenter = null
var _player: AudioStreamPlayer = null
## Real-time clock for toasts, sounds and the jump cycle — wall time, so a toast fades at the
## same rate at any playback speed.
var _clock: float = 0.0
var _last_sound_at: float = -INF
var _last_sound_tone: int = -1
## Newest first: the located alerts the jump key cycles through.
var _history: Array[Alert] = []
var _jump_index: int = -1
var _last_jump_at: float = -INF
#endregion


#region Lifecycle
func _ready() -> void:
	name = "AlertFeed"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 4)
	_player = AudioStreamPlayer.new()
	_player.name = "AlertSound"
	_player.volume_db = -8.0
	add_child(_player)


## Place it: anchored after add_child, per hud-layout.md. Below the top-left bars, clear of the
## edge-pan margin so a toast never blocks a pan.
func anchor_to_left_edge() -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2(24.0, 140.0)
	custom_minimum_size = Vector2(WIDTH, 0.0)
	size = Vector2(WIDTH, 0.0)


func _process(a_delta: float) -> void:
	_clock += a_delta
	for toast: Control in _toasts():
		var age: float = _clock - float(toast.get_meta(&"born"))
		if age >= TOAST_SECONDS:
			toast.queue_free()
		elif age > TOAST_SECONDS - FADE_SECONDS:
			toast.modulate.a = (TOAST_SECONDS - age) / FADE_SECONDS


#endregion


#region Public API
func bind(a_center: AlertCenter) -> void:
	if _center != null and _center.alert_presented.is_connected(_on_presented):
		_center.alert_presented.disconnect(_on_presented)
	_center = a_center
	if _center != null:
		_center.alert_presented.connect(_on_presented)


## Jump to the newest located alert; pressed again within JUMP_CYCLE_RESET_SECONDS, to the one
## before it, and so on. False when there is nowhere to go.
func jump_to_recent() -> bool:
	var targets: Array[Alert] = history()
	if targets.is_empty():
		return false
	var cycling: bool = _clock - _last_jump_at < JUMP_CYCLE_RESET_SECONDS
	_jump_index = (_jump_index + 1) % targets.size() if cycling else 0
	_last_jump_at = _clock
	jump_requested.emit(targets[_jump_index].xz())
	return true


## Located alerts the jump key would visit, newest first: under the player's jump scope
## (GameSettings.alert_jump_scope), only news of harm unless they chose every alert.
func history() -> Array[Alert]:
	var everything: bool = GameSettings.alert_jump_scope() == GameSettings.AlertJumpScope.ALL
	var out: Array[Alert] = []
	for alert: Alert in _history:
		if everything or AlertCatalog.is_negative(alert.type):
			out.append(alert)
			if out.size() == HISTORY_SIZE:
				break
	return out


## Show `a_alert` if it is addressed to this HUD's viewer. Public so a test can feed it.
func present(a_alert: Alert) -> void:
	if a_alert.viewer_id != int(viewer.call()):
		return
	_show_toast(a_alert)
	_play_sound(a_alert)
	if a_alert.has_position:
		_history.push_front(a_alert)
		# Kept deeper than the jump cycle, so a run of completions does not push the last few
		# attacks out of a scope that skips completions.
		if _history.size() > HISTORY_SIZE * HISTORY_DEPTH_FACTOR:
			_history.pop_back()
		# A new alert is where the next press should go first.
		_jump_index = -1
		_last_jump_at = -INF


#endregion


#region Private helpers
func _on_presented(a_alert: Alert) -> void:
	present(a_alert)


func _toasts() -> Array[Control]:
	var out: Array[Control] = []
	for child: Node in get_children():
		if child is PanelContainer and not child.is_queued_for_deletion():
			out.append(child as Control)
	return out


func _show_toast(a_alert: Alert) -> void:
	# The same words about the same place while the last toast is still up: count it rather
	# than stack it. A counting type (a completion) is counted on whichever toast already says
	# it, wherever it happened, and that toast comes back to the top.
	var toasts: Array[Control] = _toasts()
	var candidates: Array[Control] = (
		toasts if AlertCatalog.counts_repeats(a_alert.type) else toasts.slice(0, 1)
	)
	for toast: Control in candidates:
		if _repeats(toast.get_meta(&"alert") as Alert, a_alert):
			var repeats: int = int(toast.get_meta(&"repeats")) + 1
			toast.set_meta(&"repeats", repeats)
			toast.set_meta(&"born", _clock)
			toast.modulate.a = 1.0
			(toast.get_meta(&"label") as Label).text = "%s  ×%d" % [a_alert.text, repeats]
			_refresh_toast_target(toast, a_alert)
			move_child(toast, 0)
			return
	var toast := _build_toast(a_alert)
	add_child(toast)
	move_child(toast, 0)
	while _toasts().size() > MAX_TOASTS:
		var oldest: Control = _toasts().back()
		remove_child(oldest)
		oldest.queue_free()


func _build_toast(a_alert: Alert) -> PanelContainer:
	var toast := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.09, 0.85)
	style.border_color = ACCENTS[AlertCatalog.tone_of(a_alert.type)]
	style.border_width_left = 4
	style.content_margin_left = 10.0
	style.content_margin_right = 8.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	toast.add_theme_stylebox_override("panel", style)
	toast.custom_minimum_size = Vector2(WIDTH, 0.0)

	var label := Label.new()
	label.text = a_alert.text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 14)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.add_child(label)

	toast.set_meta(&"born", _clock)
	toast.set_meta(&"repeats", 1)
	toast.set_meta(&"label", label)
	toast.gui_input.connect(_on_toast_input.bind(toast))
	_refresh_toast_target(toast, a_alert)
	return toast


## Whether `a_new` says what `a_old` said, about the same place — so one toast can count both.
## A counting type needs only the same words; the toast then jumps to the newest.
static func _repeats(a_old: Alert, a_new: Alert) -> bool:
	if a_old == null or a_old.text != a_new.text or a_old.has_position != a_new.has_position:
		return false
	if not a_old.has_position or AlertCatalog.counts_repeats(a_new.type):
		return true
	return a_old.xz().distance_to(a_new.xz()) < AlertCatalog.suppress_radius(a_new.type)


## Make the toast clickable exactly when its alert may say where.
func _refresh_toast_target(a_toast: Control, a_alert: Alert) -> void:
	a_toast.set_meta(&"alert", a_alert)
	if a_alert.has_position:
		a_toast.mouse_filter = Control.MOUSE_FILTER_STOP
		a_toast.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		a_toast.tooltip_text = "Click to look"
		a_toast.add_to_group(RTSController.SELECTION_BLOCKING_UI_GROUP)
	else:
		a_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
		a_toast.tooltip_text = ""
		a_toast.remove_from_group(RTSController.SELECTION_BLOCKING_UI_GROUP)


func _on_toast_input(a_event: InputEvent, a_toast: Control) -> void:
	var press := a_event as InputEventMouseButton
	if press == null or not press.pressed or press.button_index != MOUSE_BUTTON_LEFT:
		return
	var alert := a_toast.get_meta(&"alert") as Alert
	if alert != null and alert.has_position:
		jump_requested.emit(alert.xz())
		accept_event()


func _play_sound(a_alert: Alert) -> void:
	var tone: int = int(AlertCatalog.tone_of(a_alert.type))
	var quiet: bool = _clock - _last_sound_at < SOUND_GAP_SECONDS
	if quiet and tone <= _last_sound_tone:
		return
	_last_sound_at = _clock
	_last_sound_tone = tone
	if _player == null or not _player.is_inside_tree():
		return
	_player.stream = sound_for(a_alert)
	_player.play()


## The clip `a_alert` plays: its purchase's own, when one exists, else its catalog sound.
static func sound_for(a_alert: Alert) -> AudioStream:
	if a_alert.purchase != &"" and PURCHASE_SOUNDS.has(a_alert.purchase):
		return PURCHASE_SOUNDS[a_alert.purchase]
	return SOUNDS[AlertCatalog.sound_of(a_alert.type)]
#endregion
