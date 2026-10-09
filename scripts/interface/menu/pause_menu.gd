class_name PauseMenu
extends CanvasLayer

## The in-scenario pause screen. `show_pause_menu` (Escape) raises it, the same key drops it,
## and while it is up the simulation is held. It offers the way out of a running scenario:
## back to the title screen, through SceneManager — the same call the victory dialog's return
## button makes — and, under `debug_allowed`, the playback-speed controls (PlaybackControls),
## and while the debug view is up, the match summary read from the match's event log.
##
## A CanvasLayer of its own, ABOVE ScenarioDialogView's: a pause menu that a scripted dialog
## could cover would be unreachable exactly when the player most wants to leave.
##
## ── On the pause ──
##
## Taken as a SimulationClock hold (REASON_PAUSE_MENU), not as a direct write to
## SceneTree.paused, so it COMPOSES with holds a scripted dialog or the help book may already
## have out: closing this menu resumes the world only if nothing else still wants it stopped.
## A direct write would have let closing the pause menu resume a world that a victory dialog
## was deliberately holding.
##
## Owned by Scenario, not the player rig, so a spectator session has one too.
##
## Without a clock — a menu instanced outside a Scenario, as a test does — it still opens and
## still navigates; it just doesn't stop anything. Being unable to pause is a much smaller
## problem than being unable to quit.
##
## ── Scope ──
##
## The rest of the HUD stays live underneath, because RTSController is PROCESS_MODE_ALWAYS
## and the hold only suppresses _physics_process. So the player can still pan the camera and
## queue orders behind this menu, exactly as they can behind the help book. That is the
## existing meaning of "paused" in this project (see SimulationClock), not an oversight — but
## it does mean this is a pause menu, not a modal.

#region Constants
## The live pause menu joins this group, so anything that needs it can find it without a path.
const GROUP: StringName = &"pause_menu"

## The toggle. Escape also drives Godot's built-in `ui_cancel`; Buttons don't consume that,
## so the event still reaches _unhandled_input here.
const ACTION: StringName = &"show_pause_menu"

## Above ScenarioDialogView's layer 10 — see the class comment.
const LAYER: int = 20
#endregion

#region Properties
@onready var _return_button: Button = %ReturnButton
@onready var _volume_slider: HSlider = %VolumeSlider
@onready var _playback_controls: PlaybackControls = %PlaybackControls
@onready var _match_summary: MatchSummaryView = %MatchSummary

## The scenario's clock, supplied by Scenario.bind. Null in a scene with no trigger manager.
var _clock: SimulationClock = null
## The match's event log, supplied by Scenario. Null outside a scenario: no summary is offered.
var _match_log: MatchLog = null

var _open: bool = false

## Every AudioStreamPlayer in the game (the command barks, the death sounds) is left on its
## default bus, which is this one — so driving Master's volume is driving "the game sounds"
## in their entirety, with no separate SFX bus to introduce for it.
var _master_bus_index: int = AudioServer.get_bus_index("Master")
#endregion


#region Lifecycle
func _ready() -> void:
	layer = LAYER
	# The whole point of a pause menu is that it still works while the world is stopped.
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group(GROUP)
	visible = false
	_return_button.pressed.connect(return_to_main_menu)
	# Reads back whatever the bus is already at, so re-opening this menu — or a fresh one in
	# the next scenario — picks up wherever the player last left it. AudioServer is a
	# singleton that outlives any one scene, which is the entire persistence mechanism this
	# needs for a runtime-only setting; nothing is written to disk.
	_volume_slider.value = _current_volume()
	_volume_slider.value_changed.connect(_on_volume_changed)


func _unhandled_input(a_event: InputEvent) -> void:
	if not a_event.is_action_pressed(ACTION):
		return
	toggle()
	get_viewport().set_input_as_handled()


## Never leave the world held because the scene went away with the menu open.
func _exit_tree() -> void:
	if _open and _clock != null:
		_clock.release(SimulationClock.REASON_PAUSE_MENU)
		_open = false


#endregion


#region Public API
## Give the menu the scenario's clock. Called by Scenario when it builds the menu; idempotent.
func bind(a_manager: ScenarioTriggerManager) -> void:
	_clock = a_manager.simulation_clock
	_playback_controls.bind(_clock, a_manager.is_playback())


## Give the menu the match's event log, which its summary reads.
func bind_match_log(a_log: MatchLog) -> void:
	_match_log = a_log


func is_open() -> bool:
	return _open


func toggle() -> void:
	if _open:
		close()
	else:
		open()


func open() -> void:
	if _open:
		return
	_open = true
	if _clock != null:
		_clock.hold(SimulationClock.REASON_PAUSE_MENU)
	visible = true
	# Re-read on every open: debug permission and the speed can both change while closed.
	_playback_controls.refresh()
	_match_summary.visible = DebugMode.is_active() and _match_log != null
	if _match_summary.visible:
		_match_summary.present(_match_log, "Match so far")
	# So the menu is operable from the keyboard the moment it appears.
	_return_button.grab_focus()


func close() -> void:
	if not _open:
		return
	_open = false
	if _clock != null:
		_clock.release(SimulationClock.REASON_PAUSE_MENU)
	visible = false


## Leave the scenario. Deliberately does NOT close the menu or release the hold first:
## SceneManager clears the tree-wide pause as part of the transition, and this whole node is
## about to be freed with the scene.
func return_to_main_menu() -> void:
	SceneManager.to_main_menu()


#endregion


#region Private helpers
## Master's current volume as the slider's 0..1 linear scale. Muted reads as 0 rather than
## whatever dB the bus was left at, so a menu opened while muted starts the slider at the
## bottom instead of contradicting what the player is actually hearing (silence).
func _current_volume() -> float:
	if AudioServer.is_bus_mute(_master_bus_index):
		return 0.0
	return db_to_linear(AudioServer.get_bus_volume_db(_master_bus_index))


## Mute below the slider's own floor rather than feeding 0 to linear_to_db, which is -inf.
func _on_volume_changed(a_value: float) -> void:
	AudioServer.set_bus_mute(_master_bus_index, a_value <= 0.0)
	if a_value > 0.0:
		AudioServer.set_bus_volume_db(_master_bus_index, linear_to_db(a_value))
#endregion
