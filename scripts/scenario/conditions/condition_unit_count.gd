class_name ConditionUnitCount
extends Condition

enum Comparison { AT_LEAST, AT_MOST, EXACTLY }

@export var commander_id: int = 1
## UNDEFINED matches units of any type.
@export var unit_type: Entity.Type = Entity.Type.UNDEFINED
@export var comparison: Comparison = Comparison.AT_LEAST
@export var count: int = 1

func evaluate(manager: ScenarioEventManager) -> bool:
	var commander: Commander = manager.get_commander(commander_id)
	if commander == null:
		return false
	var units: Array = commander.get_children().filter(
		func(n: Node) -> bool:
			return n is Commandable and (n as Commandable).is_in_group("unit") \
				and (unit_type == Entity.Type.UNDEFINED or (n as Commandable).type == unit_type)
	)
	var n := units.size()
	match comparison:
		Comparison.AT_LEAST: return n >= count
		Comparison.AT_MOST:  return n <= count
		Comparison.EXACTLY:  return n == count
	return false
