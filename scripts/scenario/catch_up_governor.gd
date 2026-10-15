class_name CatchUpGovernor
extends Node

## Turns the engine's catch-up off while the simulation cannot keep real time, and back on once
## it can (CatchUpPolicy says when). Catching up off means one engine step per drawn frame:
## the game slows down smoothly rather than freezing and bursting. Timing only — a tick means
## the same either way, so a replay or a networked match is unaffected.
##
## While catch-up is off, a session that permits debug says so on screen, with the speed the
## game is running at, so a slow stretch is never mistaken for a slow piece.
##
## Leaves the cap alone while PlaybackSpeed runs uncapped, which sets its own.

## Steps per frame while catching up is off.
const LOWERED_STEPS_PER_FRAME: int = 1
## Above the HUD, below the pause menu.
const OVERLAY_LAYER: int = 90
const OVERLAY_MARGIN: float = 8.0

var _policy := CatchUpPolicy.new()
var _overlay: Label = null


func _ready() -> void:
	# Measures only steps the simulation ran: during a hold there are none, and the last
	# answer stands until the world resumes.
	process_mode = Node.PROCESS_MODE_PAUSABLE
	if DebugMode.is_allowed():
		_overlay = _make_overlay()


func _exit_tree() -> void:
	if _policy.is_lowered:
		Engine.max_physics_steps_per_frame = PlaybackSpeed.default_steps_per_frame()


func _physics_process(_a_delta: float) -> void:
	if PlaybackSpeed.is_uncapped():
		return
	# Real time per engine step, which is what a frame has to fit — the engine rate, not the
	# simulation's: at a debug playback speed the two differ (TimeUtils).
	var budget: float = 1.0 / Engine.physics_ticks_per_second
	var cost: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
	var was_lowered: bool = _policy.is_lowered
	var is_lowered: bool = _policy.observe(cost, budget)
	if was_lowered and not is_lowered:
		Engine.max_physics_steps_per_frame = PlaybackSpeed.default_steps_per_frame()
	# Re-asserted every step while off: a playback-speed change writes its own cap.
	if is_lowered:
		Engine.max_physics_steps_per_frame = LOWERED_STEPS_PER_FRAME
	if _overlay != null:
		_overlay.visible = is_lowered
		if is_lowered:
			_overlay.text = (
				"Simulation behind: running at %d%% speed (catch-up off)"
				% roundi(100.0 * _policy.speed_fraction())
			)


func _make_overlay() -> Label:
	var layer := CanvasLayer.new()
	layer.layer = OVERLAY_LAYER
	add_child(layer)
	var label := Label.new()
	label.name = "CatchUpOverlay"
	label.visible = false
	label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	label.position.y = OVERLAY_MARGIN
	label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	label.add_theme_constant_override(&"outline_size", 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(label)
	return label
