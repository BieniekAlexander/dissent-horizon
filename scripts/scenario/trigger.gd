class_name Trigger
extends Resource

enum ConditionMode {
	## All conditions must be true for the trigger to fire.
	AND,
	## Any one condition being true fires the trigger.
	OR
}

## Human-readable label shown in the inspector and debug output.
@export var label: String = ""
@export var conditions: Array[Condition] = []
@export var condition_mode: ConditionMode = ConditionMode.AND
@export var events: Array[ScenarioEvent] = []
## When true the trigger disables itself after firing once.
@export var one_shot: bool = true
## When true the trigger starts inactive; use EventChainTrigger to enable it.
@export var starts_disabled: bool = false

## Runtime state — not serialized. Set to starts_disabled default by
## ScenarioEventManager._ready(); mutated by EventChainTrigger at runtime.
var enabled: bool = true


func is_satisfied(manager: ScenarioEventManager) -> bool:
	if conditions.is_empty():
		return false
	if condition_mode == ConditionMode.AND:
		return conditions.all(func(c: Condition) -> bool: return c.evaluate(manager))
	return conditions.any(func(c: Condition) -> bool: return c.evaluate(manager))


func fire(manager: ScenarioEventManager) -> void:
	for event: ScenarioEvent in events:
		event.execute(manager)
	if one_shot:
		enabled = false
	else:
		for condition: Condition in conditions:
			condition.reset()
