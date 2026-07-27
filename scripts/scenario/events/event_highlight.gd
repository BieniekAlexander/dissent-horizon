@tool
class_name EventHighlight
extends AbstractEvent

## Marks in the world what a trigger is waiting for, so the player can see the objective
## instead of only reading it.
##
## It does not describe the marks itself. It asks the trigger's own Conditions what they are
## about (Condition.highlight_entities / Condition.highlight_shapes) and paints the answer —
## so "kill the units in this area" highlights those units, "get a unit into this region"
## paints that region, and the marks stay correct as the condition's set changes. Composition
## already decided what the objective means; this just renders that decision.
##
## Two ways to use it, and the default is the one you almost always want:
##
##  * As a child of the trigger it describes, with follow_trigger_lifetime on (the default).
##    The trigger raises the highlight when it arms and drops it when it fires or is
##    disabled — so an Objective's marks are up exactly while that objective is the current
##    one, with no extra wiring. execute() is deliberately inert in this mode: fire() runs
##    every child event, and a highlight that turned itself ON at the moment its objective
##    completed would be backwards.
##
##  * As an ordinary fired event, with follow_trigger_lifetime off and `target_trigger`
##    pointing at the trigger to describe. Then `enable` decides whether firing raises or
##    drops the highlight — the same shape as EventChainTrigger, and the way to mark a
##    LATER objective from an earlier one's completion.
##
## For anything the conditions can't name — "train a unit from THAT barracks", where the
## check is a unit count and the thing to point at is a building — add EntitySelector
## children. They run as the same pipeline EventIssueCommand uses, seeded with every
## commandable in the scene, and their result is marked alongside whatever the conditions
## contributed.

#region Properties
## Whose conditions to read. Null means the trigger this event is a child of, which is the
## normal arrangement.
@export var target_trigger: GlobalTrigger

## Raise while the target trigger is armed and drop when it fires or is disabled. Off makes
## this a normal fired event driven by `enable`.
@export var follow_trigger_lifetime: bool = true

## Fired-event mode only: true raises the highlight, false drops it.
@export var enable: bool = true

## Ask the target trigger's conditions what to mark. Turn off to mark ONLY what this node's
## EntitySelector children pick out.
@export var use_trigger_conditions: bool = true

## Marker colour, used both by the world painter and by the minimap markers for the same
## targets. Defaults to the shared objective green; override per node only when a highlight
## means something other than "this is your objective".
@export var color: Color = ScenarioHighlight.OBJECTIVE_COLOR
#endregion

#region Runtime state
## The live painter, or null while this highlight is down. Not serialized.
var _highlight: ScenarioHighlight = null
## Manager captured when the highlight was raised, so the target callback can re-query.
var _manager: ScenarioTriggerManager = null
#endregion

#region Public API
## Fired-event path. Inert in follow_trigger_lifetime mode — see the class docs for why.
func execute(a_manager: ScenarioTriggerManager) -> void:
	if follow_trigger_lifetime:
		return
	if enable:
		show_highlight(a_manager)
	else:
		hide_highlight()


## Raise the marks. Idempotent: re-showing an already-visible highlight just refreshes it.
func show_highlight(a_manager: ScenarioTriggerManager) -> void:
	_manager = a_manager
	if _highlight != null and is_instance_valid(_highlight):
		_highlight.refresh()
		return
	_highlight = ScenarioHighlight.new()
	_highlight.name = "%sHighlight" % name
	_highlight.color = color
	_highlight.map = a_manager.map
	_highlight.target_source = _collect_targets
	a_manager.highlight_parent().add_child(_highlight)
	# Populate before the first frame so the marks never flash in a frame late.
	_highlight.refresh()


## Drop the marks. Safe to call when nothing is showing.
func hide_highlight() -> void:
	if _highlight != null and is_instance_valid(_highlight):
		_highlight.queue_free()
	_highlight = null


func is_showing() -> bool:
	return _highlight != null and is_instance_valid(_highlight)


## The live painter, for tests and for HUD code that wants to know what is being marked.
func highlight() -> ScenarioHighlight:
	return _highlight
#endregion

#region Target collection
## What to mark right now: the union of the target trigger's condition-derived targets and
## this node's own selector pipeline. Handed to ScenarioHighlight as a Callable so it
## re-queries on its own cadence and the marks track a live set.
func _collect_targets() -> Dictionary:
	var entities: Array[Entity] = []
	var shapes: Array[HighlightShape] = []
	if _manager == null:
		return {"entities": entities, "shapes": shapes}

	if use_trigger_conditions:
		var trigger: GlobalTrigger = _resolve_trigger()
		if trigger != null:
			for condition: Condition in trigger.conditions:
				if condition == null:
					continue
				for entity: Entity in condition.highlight_entities(_manager):
					if entity != null and entity not in entities:
						entities.append(entity)
				shapes.append_array(condition.highlight_shapes(_manager))

	for entity: Entity in _selected_entities():
		if entity not in entities:
			entities.append(entity)

	return {"entities": entities, "shapes": shapes}


## `target_trigger` if set, otherwise the trigger this event hangs off. Walks up rather than
## checking only the immediate parent so a highlight nested inside a container event still
## finds the trigger that owns the whole subtree.
func _resolve_trigger() -> GlobalTrigger:
	if target_trigger != null:
		return target_trigger
	var node: Node = get_parent()
	while node != null:
		if node is GlobalTrigger:
			return node as GlobalTrigger
		node = node.get_parent()
	return null


## Run this node's EntitySelector children over every commandable in the scene. Empty when
## there are no selectors — the common case, where the conditions say everything.
##
## The seed is the "piece" group rather than "unit" (which is what EventIssueCommand
## seeds with), because the point of the selector path here is to mark BUILDINGS: "train a
## unit from that barracks" is a unit-count check with a structure to point at.
func _selected_entities() -> Array[Entity]:
	var selectors: Array[EntitySelector] = []
	for child: Node in get_children():
		if child is EntitySelector:
			selectors.append(child as EntitySelector)
	var entities: Array[Entity] = []
	if selectors.is_empty() or _manager == null:
		return entities
	for node: Node in _manager.get_tree().get_nodes_in_group("piece"):
		var entity := node as Entity
		if entity != null:
			entities.append(entity)
	for selector: EntitySelector in selectors:
		entities = selector.filter(entities, _manager)
	return entities
#endregion

#region Lifecycle
## A highlight whose event node leaves the tree (scenario torn down, subtree freed) must not
## leave its painter orphaned under the Map.
func _exit_tree() -> void:
	hide_highlight()
#endregion
