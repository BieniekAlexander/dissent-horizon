class_name BriefingObjectivesView
extends VBoxContainer

## The pause menu's Briefing tab: every objective the checklist has shown so far, with its details
## underneath (GlobalTrigger.details), key placeholders resolved. A finished one is struck through
## and dimmed, details and all; it is the only place a finished objective is still listed, since
## the HUD checklist drops it (ObjectiveView).

## A DialogPage's default content_width, so the Briefing and How to Play tabs read alike.
const WIDTH: float = 520.0
const DONE_MARK: String = "☑"
const OPEN_MARK: String = "☐"
const FAILURE_MARK: String = "•"
## A finished objective's text, against the pause menu's dark panel.
const DONE_COLOR: Color = Color(0.6, 0.6, 0.6)

var _manager: ScenarioTriggerManager = null


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	custom_minimum_size = Vector2(WIDTH, 0.0)
	refresh()


func bind(a_manager: ScenarioTriggerManager) -> void:
	_manager = a_manager
	if not a_manager.objectives_changed.is_connected(refresh):
		a_manager.objectives_changed.connect(refresh)
	refresh()


## Whether there is anything to brief: a skirmish has no objectives.
func has_objectives() -> bool:
	return not _objectives().is_empty()


## Each objective as plain text, mark and details included: what the tab draws, for tests.
func lines() -> Array[String]:
	var out: Array[String] = []
	for trigger: GlobalTrigger in _objectives():
		var line: String = "%s %s" % [mark(trigger), trigger.objective_text()]
		if not trigger.details.is_empty():
			line += "\n" + InputPrompt.format(trigger.details)
		out.append(line)
	return out


func refresh() -> void:
	if not is_inside_tree():
		return
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	for trigger: GlobalTrigger in _objectives():
		add_child(_row(trigger))


static func mark(a_trigger: GlobalTrigger) -> String:
	if a_trigger.scope == GlobalTrigger.ObjectiveScope.FAILURE:
		return FAILURE_MARK
	return DONE_MARK if a_trigger.has_fired else OPEN_MARK


## Whether the objective reads as finished: fired, and not a way to lose, which has no "done".
static func is_done(a_trigger: GlobalTrigger) -> bool:
	return a_trigger.scope != GlobalTrigger.ObjectiveScope.FAILURE and a_trigger.has_fired


func _objectives() -> Array[GlobalTrigger]:
	if _manager == null:
		return []
	return _manager.visible_objective_triggers()


func _row(a_trigger: GlobalTrigger) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.custom_minimum_size = Vector2(WIDTH, 0.0)
	var text: String = "[b]%s %s[/b]" % [mark(a_trigger), a_trigger.objective_text()]
	if not a_trigger.details.is_empty():
		text += "\n" + InputPrompt.format(a_trigger.details)
	if is_done(a_trigger):
		text = "[s]%s[/s]" % text
		label.add_theme_color_override("default_color", DONE_COLOR)
	label.text = text
	return label
