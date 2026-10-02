class_name ObjectiveView
extends Control

## The scenario's objective checklist: one line per player-facing GlobalTrigger (any `scope`
## but NONE), omitted entirely while it is still PENDING (a trigger no other trigger has
## revealed yet — listing it would spoil what's coming).
##
## `scope` decides how a row reads, and nothing else does — the manager orders the rows
## (FAILURE, then PRIMARY, then SECONDARY) and this only paints them:
##
##   FAILURE   red, bulleted. A way to LOSE, so there is no box to tick: a checkbox would
##             invite the player to read it as something to go and do.
##   PRIMARY   green, checkbox, struck through once fulfilled.
##   SECONDARY amber, checkbox, struck through once fulfilled — same shape as a PRIMARY,
##             since it is still a thing to tick off; only the colour says it's optional.
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

#region Constants
## Live ObjectiveViews join this group so Scenario can find and bind whichever the HUD
## happens to contain, without knowing where in the rig it was placed.
const GROUP: StringName = &"objective_view"

## Row prefixes. Constants so the strings the tests assert on live in one place.
const MARK_COMPLETE: String = "[x]"
const MARK_ACTIVE: String = "[ ]"
## A failure condition is not a task, so it gets a bullet instead of a box.
const MARK_FAILURE: String = "•"
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
#endregion


#region Lifecycle
func _ready() -> void:
	add_to_group(GROUP)
	# The checklist has to stay readable while a scripted beat holds the simulation. Set here
	# rather than relied on from the parent, so the panel behaves the same wherever it's placed.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_row_template.visible = false
	refresh()


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
	for trigger: GlobalTrigger in _manager.visible_objective_triggers():
		result.append(_row_text(trigger))
	return result


## Rebuild the list from the bound manager.
func refresh() -> void:
	if _rows == null:
		return
	for child: Node in _rows.get_children():
		if child == _row_template:
			continue
		_rows.remove_child(child)
		child.queue_free()

	var visible_objectives: Array[GlobalTrigger] = []
	if _manager != null:
		visible_objectives = _manager.visible_objective_triggers()
	for trigger: GlobalTrigger in visible_objectives:
		_rows.add_child(_make_row(trigger))

	# A scenario with no objectives (a plain skirmish) shows no panel at all.
	var any: bool = not visible_objectives.is_empty()
	_title_label.visible = any and not _title_label.text.is_empty()
	_panel.visible = any


#endregion


#region Internal
## One checklist row, duplicated from the authored template so it inherits whatever styling
## the scene gives it. Colour comes from the scope; the strike comes from the state. The [s]
## tag is why the template is a RichTextLabel.
func _make_row(a_trigger: GlobalTrigger) -> RichTextLabel:
	var label: RichTextLabel = _row_template.duplicate()
	label.visible = true
	var body: String = _row_text(a_trigger)
	label.text = "[s]%s[/s]" % body if _is_struck(a_trigger) else body
	label.add_theme_color_override("default_color", _color(a_trigger))
	return label


## A row's plain text, mark included — what rows() reports and what _make_row wraps.
func _row_text(a_trigger: GlobalTrigger) -> String:
	return "%s %s" % [_mark(a_trigger), a_trigger.objective_text()]


## Struck through once fulfilled — but never a FAILURE, which is not a box being ticked. A
## fired failure condition ends the scenario anyway, so it has no "done" reading to show.
func _is_struck(a_trigger: GlobalTrigger) -> bool:
	return (
		a_trigger.scope != GlobalTrigger.ObjectiveScope.FAILURE
		and a_trigger.objective_state() == GlobalTrigger.ObjectiveState.COMPLETE
	)


func _color(a_trigger: GlobalTrigger) -> Color:
	match a_trigger.scope:
		GlobalTrigger.ObjectiveScope.FAILURE:
			return failure_color
		GlobalTrigger.ObjectiveScope.SECONDARY:
			return secondary_color
		_:
			return primary_color


func _mark(a_trigger: GlobalTrigger) -> String:
	if a_trigger.scope == GlobalTrigger.ObjectiveScope.FAILURE:
		return MARK_FAILURE
	return (
		MARK_COMPLETE
		if a_trigger.objective_state() == GlobalTrigger.ObjectiveState.COMPLETE
		else MARK_ACTIVE
	)
#endregion
