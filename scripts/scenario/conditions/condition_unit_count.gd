class_name ConditionUnitCount
extends RegionAwareCondition

#region Properties
enum Comparison { AT_LEAST, AT_MOST, EXACTLY }

@export var commander_id: int = 1
## UNDEFINED matches units of any type.
@export var unit_type: Entity.Type = Entity.Type.UNDEFINED
@export var comparison: Comparison = Comparison.AT_LEAST
@export var count: int = 1
## Optional spatial scope is inherited from RegionAwareCondition (region_shape_path): when
## set, only units inside that CollisionShape3D are counted.
#endregion

#region Public API
func evaluate(manager: ScenarioTriggerManager) -> bool:
	var commander: Commander = manager.get_commander(commander_id)
	if commander == null:
		return false
	var units: Array = commander.get_children().filter(
		func(n: Node) -> bool:
			return n is Commandable and (n as Commandable).is_in_group("unit") \
				and (unit_type == Entity.Type.UNDEFINED or (n as Commandable).type == unit_type) \
				and region_contains((n as Commandable).global_position)
	)
	var n := units.size()
	match comparison:
		Comparison.AT_LEAST: return n >= count
		Comparison.AT_MOST:  return n <= count
		Comparison.EXACTLY:  return n == count
	return false
#endregion
