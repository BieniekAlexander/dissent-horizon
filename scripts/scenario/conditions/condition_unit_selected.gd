@tool
class_name ConditionUnitSelected
extends RegionAwareCondition

## True while the player has a matching unit selected — the check behind a tutorial's
## "click one of your units" beat.
##
## Reads Selectable.is_selected() on the commander's own entities rather than
## RTSController.selection, so it works the same whether the selection came from a click, a
## box drag, a double-click, or the idle-unit cycler — and so it needs no reference to the
## HUD at all. A pull condition: the ConditionPoller re-checks it each physics frame.
##
## The poller keeps running while a SimulationClock hold is in effect (the
## ScenarioTriggerManager is PROCESS_MODE_ALWAYS), which is what lets a paused tutorial beat
## resume on the player's selection.

#region Properties
## Whose units count as "selected". Defaults to the human player.
@export var commander_id: int = 1
## UNDEFINED matches units of any type.
@export var unit_type: StringName = &""
## When true, a structure (barracks, refinery) also satisfies the check. Off by default —
## "select a unit" is the common tutorial beat.
@export var include_structures: bool = false
## How many matching entities must be selected at once. 1 = "select any one of them".
@export var count: int = 1
## Optional spatial scope inherited from RegionAwareCondition (region_shape_path): when set,
## only entities inside that CollisionShape3D count.
#endregion

#region Public API
func evaluate(a_manager: ScenarioTriggerManager) -> bool:
	var selected: int = 0
	for candidate: Commandable in _candidates(a_manager):
		if candidate.selectable != null and candidate.selectable.is_selected():
			selected += 1
	return selected >= count
#endregion

#region Player-facing description (highlights)
## Mark every entity that WOULD satisfy the check, so the player can see what to click.
## Unlike the count conditions this is useful in the unmet state — the candidates exist
## already; the player just hasn't picked one.
func highlight_entities(a_manager: ScenarioTriggerManager) -> Array[Entity]:
	var result: Array[Entity] = []
	result.assign(_candidates(a_manager))
	return result
#endregion

#region Internal
## The commander's entities that pass the kind / type / region filters.
func _candidates(a_manager: ScenarioTriggerManager) -> Array:
	var commander: Commander = a_manager.get_commander(commander_id)
	if commander == null:
		return []
	return commander.get_children().filter(
		func(n: Node) -> bool:
			var c := n as Commandable
			if c == null:
				return false
			if not c.is_in_group("unit") and not (include_structures and c.is_in_group("structure")):
				return false
			if unit_type != &"" and c.id != unit_type:
				return false
			return region_contains(c.global_position)
	)
#endregion
