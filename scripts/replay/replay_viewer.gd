class_name ReplayViewer
extends CanvasLayer

## How a playback is watched: the replay-only keys — pause, slower, faster, switch view — and a
## banner saying what is on screen. Scenario creates one for a playback, never for a match.
## gdd/systems/commands/recording-and-replay.md §Watching.
##
## Nothing here reaches the simulation. Pausing is a SimulationClock hold (the debug playback
## pause's reason, so the pause menu's toggle agrees with it), speed is PlaybackSpeed, and a view
## is which commander's Fog is displayed (Fog.active_commander_id) — never the local player, which
## the simulation reads (the implicit elimination rule), so switching it would play a different
## match.
##
## A playback is a spectator session (Scenario._build_commanders): the spectator camera, its HUD
## and its panel's views, fog toggle and speed controls are the watcher's, and this adds only the
## keys and the banner. The keys may
## share the command grid's positional keys, since a spectator session has no grid.

const ACTION_PAUSE: StringName = &"replay_pause"
const ACTION_SLOWER: StringName = &"replay_slower"
const ACTION_FASTER: StringName = &"replay_faster"
const ACTION_SWITCH_VIEW: StringName = &"replay_switch_view"
## The speeds the keys step through, as multiples of real time. Within PlaybackSpeed's range.
const SPEEDS: Array[float] = [0.25, 0.5, 1.0, 2.0, 4.0]
## Above the HUD, below the dialog view and the pause menu.
const LAYER: int = 8

var _scenario: Scenario = null
var _clock: SimulationClock = null
var _banner: Label = null


func _ready() -> void:
	layer = LAYER
	# Put away with the rest of the HUD by its hide button.
	add_to_group(RTSController.HUD_LAYER_GROUP)
	# The keys have to work while the world is held — that is what un-pausing is.
	process_mode = Node.PROCESS_MODE_ALWAYS
	var panel := PanelContainer.new()
	panel.name = "Banner"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.position.y = 8.0
	add_child(panel)
	_banner = Label.new()
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(_banner)
	_refresh()


## Watch `a_scenario`'s playback, pausing through `a_clock` (null: the pause key does nothing).
func bind(a_scenario: Scenario, a_clock: SimulationClock) -> void:
	_scenario = a_scenario
	_clock = a_clock
	_refresh()


## Every frame: the spectator panel's speed controls, view buttons and fog toggle change what
## the banner reports without passing through here.
func _process(_a_delta: float) -> void:
	_refresh()


func _unhandled_input(a_event: InputEvent) -> void:
	if a_event.is_echo():
		return
	if a_event.is_action_pressed(ACTION_PAUSE):
		toggle_pause()
	elif a_event.is_action_pressed(ACTION_SLOWER):
		step_speed(-1)
	elif a_event.is_action_pressed(ACTION_FASTER):
		step_speed(1)
	elif a_event.is_action_pressed(ACTION_SWITCH_VIEW):
		switch_view()
	else:
		return
	get_viewport().set_input_as_handled()


#region Public API
func is_paused() -> bool:
	return _clock != null and _clock.is_held_by(SimulationClock.REASON_PLAYBACK_PAUSE)


func toggle_pause() -> void:
	if _clock == null:
		return
	if is_paused():
		_clock.release(SimulationClock.REASON_PLAYBACK_PAUSE)
	else:
		_clock.hold(SimulationClock.REASON_PLAYBACK_PAUSE)
	_refresh()


## One step along SPEEDS: up for a positive `a_direction`, down for a negative one.
func step_speed(a_direction: int) -> void:
	PlaybackSpeed.set_multiplier(next_speed(PlaybackSpeed.multiplier(), a_direction))
	_refresh()


## The next view after the one on screen: each commander that keeps a fog, in id order, then
## round again.
func switch_view() -> void:
	Fog.active_commander_id = next_view(views(), current_view())
	_refresh()


## The views on offer: every commander with a Fog of its own (an omniscient slot keeps none, and
## has no view to show).
func views() -> Array[int]:
	var out: Array[int] = []
	if _scenario != null:
		for commander: Commander in _scenario.commanders:
			if commander.id > 0 and Fog.for_commander(commander.id) != null:
				out.append(commander.id)
	return out


## The view on screen, with the "the local player's" default (-1) resolved to that player's id.
func current_view() -> int:
	var active: int = Fog.active_commander_id
	return RTSController.PLAYER_COMMANDER_ID if active == -1 else active


## What the banner says.
func banner_text() -> String:
	var seen: String = "Commander %d" % current_view()
	if Fog.is_lifted():
		seen += ", no fog"
	var parts: PackedStringArray = [
		"REPLAY",
		PlaybackSpeed.label_for(PlaybackSpeed.multiplier(), PlaybackSpeed.is_uncapped()),
		"viewing %s" % seen,
	]
	if is_paused():
		parts.insert(1, "paused")
	var keys: String = (
		"%s pause · %s slower · %s faster · %s switch view"
		% [
			InputPrompt.action_text(ACTION_PAUSE),
			InputPrompt.action_text(ACTION_SLOWER),
			InputPrompt.action_text(ACTION_FASTER),
			InputPrompt.action_text(ACTION_SWITCH_VIEW),
		]
	)
	return "  ·  ".join(parts) + "\n" + keys


#endregion


#region Pure rules
## The speed one step from `a_current` along SPEEDS — from the step nearest it, so a speed set
## elsewhere (the spectator panel's slider) still steps sensibly — held at either end.
static func next_speed(a_current: float, a_direction: int) -> float:
	var nearest: int = 0
	for i: int in SPEEDS.size():
		if absf(SPEEDS[i] - a_current) < absf(SPEEDS[nearest] - a_current):
			nearest = i
	return SPEEDS[clampi(nearest + signi(a_direction), 0, SPEEDS.size() - 1)]


## The view after `a_current` in `a_views`, wrapping; the first when `a_current` is not one.
static func next_view(a_views: Array[int], a_current: int) -> int:
	if a_views.is_empty():
		return a_current
	var at: int = a_views.find(a_current)
	return a_views[(at + 1) % a_views.size()]


#endregion


func _refresh() -> void:
	if _banner != null:
		_banner.text = banner_text()
