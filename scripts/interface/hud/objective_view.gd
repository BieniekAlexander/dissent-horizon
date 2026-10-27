class_name ObjectiveView
extends Control

## The scenario's objective checklist: one line per player-facing GlobalTrigger (any `scope`
## but NONE) that is still to do. A PENDING one (no other trigger has revealed it yet) is
## omitted, since listing it would spoil what's coming; a COMPLETE one is omitted too, as the
## pause menu's Briefing tab keeps the record of what is done (BriefingObjectivesView).
##
## `scope` decides how a row reads, and nothing else does — the manager orders the rows
## (FAILURE, then PRIMARY, then SECONDARY) and this only paints them:
##
##   FAILURE   red, bulleted. A way to LOSE, so there is no box to tick: a checkbox would
##             invite the player to read it as something to go and do.
##   PRIMARY   green, checkbox.
##   SECONDARY amber, checkbox — same shape as a PRIMARY, since it is still a thing to tick
##             off; only the colour says it's optional.
##
## The LAYOUT is authored, in scenes/interface/objective_view.tscn, and instanced into the
## player HUD (scenes/player.tscn) alongside the other panels. This script only decides which
## rows exist and what they say; where the panel sits, how it's styled, and what the heading
## reads are all inspector work. Everything it touches is looked up by scene-unique name, so
## the tree inside that scene can be rearranged freely.
##
## New rows are duplicated from %RowTemplate — a hidden node in the same scene — rather than
## built in code, so restyling a row is editing one node instead of editing a function.
##
## Repaints off ScenarioTriggerManager.objectives_changed rather than polling, and rebuilds
## the whole list each time: it's a handful of rows, and rebuilding removes any way for a row
## to drift out of sync with its trigger.
##
## A newly listed objective is ANNOUNCED: its row flashes and a chime plays, once. The cue waits
## while a pop-up is open or the pause menu is up, so it lands when the player is looking at the
## HUD again rather than behind a modal panel. Real time, so it reads the same at any playback
## speed. gdd/systems/scenario-scripting/objectives-and-completion.md §A new objective is
## announced.

#region Constants
## Live ObjectiveViews join this group so Scenario can find and bind whichever the HUD
## happens to contain, without knowing where in the rig it was placed.
const GROUP: StringName = &"objective_view"

## Row prefixes. Constants so the strings the tests assert on live in one place.
const MARK_ACTIVE: String = "[ ]"
## A failure condition is not a task, so it gets a bullet instead of a box.
const MARK_FAILURE: String = "•"

const ANNOUNCE_SOUND: AudioStream = preload("res://assets/audio/alerts/objective_added.wav")
## Real seconds a new row flashes for, and one on-off blink within it.
const FLASH_SECONDS: float = 3.0
const FLASH_PERIOD_SECONDS: float = 0.5
## A flashing row's opacity in the off half of a blink: dimmed, not gone, so it stays readable.
const FLASH_DIM_ALPHA: float = 0.25
## The cue sits under unit barks, as the alert tones do (AlertFeed).
const ANNOUNCE_VOLUME_DB: float = -8.0
#endregion

#region Signals
## A batch of newly listed objectives was announced: their rows began to flash and the chime played.
signal objectives_announced(triggers: Array[GlobalTrigger])
#endregion

#region Properties
@export_category("Objective rows")
## Colour of a PRIMARY objective, done or not.
@export var primary_color: Color = Color(0.35, 0.85, 0.4)
## Colour of a SECONDARY (optional) objective, done or not.
@export var secondary_color: Color = Color(1.0, 0.85, 0.15)
## Colour of a FAILURE condition — the way to lose.
@export var failure_color: Color = Color(0.9, 0.3, 0.3)

@onready var _panel: Control = %Panel
@onready var _title_label: Label = %Title
@onready var _rows: Control = %Rows
@onready var _row_template: RichTextLabel = %RowTemplate

var _manager: ScenarioTriggerManager
## Every objective ever listed, announced or waiting to be, so each is announced once.
var _seen: Array[GlobalTrigger] = []
## Listed but not yet announced, held back by a pop-up or the pause menu.
var _pending: Array[GlobalTrigger] = []
## Announced objectives still flashing, by the real time their flash began.
var _flash_started: Dictionary = {}
## Real seconds since this view was ready: the flash's clock, unaffected by playback speed.
var _clock: float = 0.0
var _sound: AudioStreamPlayer
#endregion


#region Lifecycle
func _ready() -> void:
	add_to_group(GROUP)
	# The checklist has to stay readable while a scripted beat holds the simulation. Set here
	# rather than relied on from the parent, so the panel behaves the same wherever it's placed.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_row_template.visible = false
	_sound = AudioStreamPlayer.new()
	_sound.name = "AnnounceSound"
	_sound.stream = ANNOUNCE_SOUND
	_sound.volume_db = ANNOUNCE_VOLUME_DB
	add_child(_sound)
	refresh()


func _process(a_delta: float) -> void:
	_clock += a_delta
	if not _pending.is_empty() and not _is_covered():
		_announce_pending()
	_update_flashes()


## Watch a trigger manager's objectives. Called by Scenario once both exist; idempotent, so
## re-binding can't double-subscribe.
func bind(a_manager: ScenarioTriggerManager) -> void:
	if _manager == a_manager:
		return
	_manager = a_manager
	if not a_manager.objectives_changed.is_connected(refresh):
		a_manager.objectives_changed.connect(refresh)
	refresh()


#endregion


#region Public API
## The lines currently displayed, top to bottom, as plain text — the view's own account of
## itself, and what tests assert against rather than walking Labels.
func rows() -> Array[String]:
	var result: Array[String] = []
	if _manager == null:
		return result
	for trigger: GlobalTrigger in _open_objectives():
		result.append(_row_text(trigger))
	return result


## Whether `a_trigger`'s row is flashing as a newly announced objective.
func is_flashing(a_trigger: GlobalTrigger) -> bool:
	return _flash_started.has(a_trigger)


## Whether `a_trigger` is listed but its announcement is still held back.
func is_awaiting_announcement(a_trigger: GlobalTrigger) -> bool:
	return _pending.has(a_trigger)


## Rebuild the list from the bound manager.
func refresh() -> void:
	if _rows == null:
		return
	for child: Node in _rows.get_children():
		if child == _row_template:
			continue
		_rows.remove_child(child)
		child.queue_free()

	var visible_objectives: Array[GlobalTrigger] = _open_objectives()
	for trigger: GlobalTrigger in visible_objectives:
		if not _seen.has(trigger):
			_seen.append(trigger)
			_pending.append(trigger)
		_rows.add_child(_make_row(trigger))
	_update_flashes()

	# A scenario with no objectives (a plain skirmish) shows no panel at all.
	var any: bool = not visible_objectives.is_empty()
	_title_label.visible = any and not _title_label.text.is_empty()
	_panel.visible = any


#endregion


#region Internal
## The revealed objectives not yet done, in the manager's order. A FAILURE never reads as done:
## firing one ends the scenario, so it stays listed.
func _open_objectives() -> Array[GlobalTrigger]:
	var result: Array[GlobalTrigger] = []
	if _manager == null:
		return result
	for trigger: GlobalTrigger in _manager.visible_objective_triggers():
		if (
			trigger.scope == GlobalTrigger.ObjectiveScope.FAILURE
			or trigger.objective_state() != GlobalTrigger.ObjectiveState.COMPLETE
		):
			result.append(trigger)
	return result


## Whether something covers the HUD the player would need to see the cue on: a pop-up waiting on
## them, or the pause menu.
func _is_covered() -> bool:
	if _manager == null:
		return false
	var clock: SimulationClock = _manager.simulation_clock
	return (
		_manager.has_open_dialog()
		or (clock != null and clock.is_held_by(SimulationClock.REASON_PAUSE_MENU))
	)


## Start every held-back row flashing, with one chime for the batch. A row that left the
## checklist meanwhile (done behind the pop-up) is not announced.
func _announce_pending() -> void:
	var listed: Array[GlobalTrigger] = _open_objectives()
	var announced: Array[GlobalTrigger] = []
	for trigger: GlobalTrigger in _pending:
		if listed.has(trigger):
			_flash_started[trigger] = _clock
			announced.append(trigger)
	_pending.clear()
	if announced.is_empty():
		return
	if _sound != null and _sound.is_inside_tree():
		_sound.play()
	objectives_announced.emit(announced)


## Blink each flashing row and end the flashes that have run their course.
func _update_flashes() -> void:
	for trigger: GlobalTrigger in _flash_started.keys():
		if _clock - float(_flash_started[trigger]) >= FLASH_SECONDS:
			_flash_started.erase(trigger)
	if _rows == null:
		return
	for row: Node in _rows.get_children():
		if row == _row_template or not row.has_meta(&"trigger"):
			continue
		var trigger: GlobalTrigger = row.get_meta(&"trigger")
		var is_dim: bool = (
			_flash_started.has(trigger)
			and (
				fmod(_clock - float(_flash_started[trigger]), FLASH_PERIOD_SECONDS)
				>= FLASH_PERIOD_SECONDS * 0.5
			)
		)
		(row as CanvasItem).modulate.a = FLASH_DIM_ALPHA if is_dim else 1.0


## One checklist row, duplicated from the authored template so it inherits whatever styling
## the scene gives it. Colour comes from the scope.
func _make_row(a_trigger: GlobalTrigger) -> RichTextLabel:
	var label: RichTextLabel = _row_template.duplicate()
	label.visible = true
	label.text = _row_text(a_trigger)
	label.add_theme_color_override("default_color", _color(a_trigger))
	label.set_meta(&"trigger", a_trigger)
	return label


## A row's plain text, mark included — what rows() reports and what _make_row wraps.
func _row_text(a_trigger: GlobalTrigger) -> String:
	return "%s %s" % [_mark(a_trigger), a_trigger.objective_text()]


func _color(a_trigger: GlobalTrigger) -> Color:
	match a_trigger.scope:
		GlobalTrigger.ObjectiveScope.FAILURE:
			return failure_color
		GlobalTrigger.ObjectiveScope.SECONDARY:
			return secondary_color
		_:
			return primary_color


func _mark(a_trigger: GlobalTrigger) -> String:
	return MARK_FAILURE if a_trigger.scope == GlobalTrigger.ObjectiveScope.FAILURE else MARK_ACTIVE
#endregion
