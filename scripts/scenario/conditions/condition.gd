class_name Condition
extends Resource

## Returns true when this condition is met. Called every physics tick by Trigger.
func evaluate(_manager: ScenarioEventManager) -> bool:
	return false

## Called when the owning Trigger resets after firing (repeating triggers only).
## Override to clear any internal per-fire state.
func reset() -> void:
	pass
