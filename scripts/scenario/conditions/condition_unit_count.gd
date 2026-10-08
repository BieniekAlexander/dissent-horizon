@tool
class_name ConditionUnitCount
extends RegionAwareCondition

#region Properties
enum Comparison { AT_LEAST, AT_MOST, EXACTLY }

@export var commander_id: int = 1
## UNDEFINED matches units of any type.
@export var unit_type: StringName = &""
@export var comparison: Comparison = Comparison.AT_LEAST
@export var count: int = 1
## Optional spatial scope is inherited from RegionAwareCondition (region_shape_path): when
## set, only units inside that CollisionShape3D are counted.
#endregion


#region Public API
func evaluate(a_manager: ScenarioTriggerManager) -> bool:
	var n: int = matching_units(a_manager).size()
	match comparison:
		Comparison.AT_LEAST:
			return n >= count
		Comparison.AT_MOST:
			return n <= count
		Comparison.EXACTLY:
			return n == count
	return false


#endregion


#region Player-facing description (highlights)
## AT_MOST is the "get rid of these" shape of the check — the matching units ARE the task,
## so mark them and let the marks vanish as they die. AT_LEAST / EXACTLY are waiting on
## units that don't exist yet, so there is nothing to point at; the inherited region
## footprint (RegionAwareCondition.highlight_shapes) carries "bring them HERE" instead.
func highlight_entities(a_manager: ScenarioTriggerManager) -> Array[Entity]:
	var result: Array[Entity] = []
	if comparison != Comparison.AT_MOST:
		return result
	result.assign(matching_units(a_manager))
	return result


#endregion


#region Internal
## Every unit the commander owns that passes the type and region filters — the set both
## evaluate() counts and highlight_entities() marks, so what the player sees marked can
## never drift from what the check is actually measuring.
func matching_units(a_manager: ScenarioTriggerManager) -> Array:
	var commander: Commander = a_manager.get_commander(commander_id)
	if commander == null:
		return []
	return commander.get_children().filter(
		func(n: Node) -> bool:
			return (
				n is Actor
				and (n as Actor).is_in_group("unit")
				and (unit_type == &"" or (n as Actor).id == unit_type)
				and region_contains((n as Actor).global_position)
			)
	)
#endregion
