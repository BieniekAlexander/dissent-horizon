class_name ConditionUnitHasNoCommandFor
extends Condition

## True once a commander's unit(s) have held NO command continuously for [member ticks]
## physics ticks. A pull condition that tracks an idle streak: any tick a matching unit
## has a command, the streak resets. Use it to assert the bot deliberately leaves a unit
## alone — e.g. "the kamikaze should sit idle (not be sent to attack) for 10 seconds when
## there's no worthwhile blast target".
##
## With `unit_type` = UNDEFINED every unit the commander owns must be command-free. The
## streak also resets if no matching unit exists, so a dead/never-spawned unit can't pass
## vacuously.

#region Properties
## Which commander's units to inspect.
@export var commander_id: int = 1
## UNDEFINED matches units of any type.
@export var unit_type: StringName = &""
## Continuous command-free physics ticks required (30 ticks = 1 second).
@export var ticks: int = 300
#endregion

## Physics tick the current command-free streak began, or -1 when not idle.
var _idle_since: int = -1


#region Public API
func evaluate(manager: ScenarioTriggerManager) -> bool:
	var now: int = manager.scenario.frame
	if not _all_idle(manager):
		_idle_since = -1
		return false
	if _idle_since < 0:
		_idle_since = now
	return (now - _idle_since) >= ticks


func reset() -> void:
	super.reset()
	_idle_since = -1
#endregion

#region Internal
## True when every matching unit currently holds no command. False (streak-breaking) when
## no matching unit exists, so the check can't pass on an empty set.
func _all_idle(manager: ScenarioTriggerManager) -> bool:
	var commander: Commander = manager.get_commander(commander_id)
	if commander == null:
		return false
	var units: Array = commander.get_children().filter(
		func(n: Node) -> bool:
			return n is Commandable and (n as Commandable).is_in_group("unit") \
				and (unit_type == &"" or (n as Commandable).id == unit_type)
	)
	if units.is_empty():
		return false
	return units.all(func(u: Commandable) -> bool: return not u.has_command())
#endregion
