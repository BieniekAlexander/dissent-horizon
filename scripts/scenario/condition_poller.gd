class_name ConditionPoller
extends Node

## Drives PULL-based Conditions. Every physics frame it re-checks each registered
## Condition (via Condition.poll → evaluate), so conditions that can't announce their
## own changes — live state checks like ConditionUnitCount or ConditionUnitsInRegion —
## still nudge their owning GlobalTrigger on a truth edge. PUSH conditions never register
## here; they ride signal buses instead. Owned/created by ScenarioTriggerManager._ready.

var manager: ScenarioTriggerManager

var _conditions: Array[Condition] = []

#region Registration
func add(condition: Condition) -> void:
	if condition not in _conditions:
		_conditions.append(condition)


func remove(condition: Condition) -> void:
	_conditions.erase(condition)
#endregion

#region Lifecycle
func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	for condition: Condition in _conditions:
		condition.poll(manager)
#endregion
