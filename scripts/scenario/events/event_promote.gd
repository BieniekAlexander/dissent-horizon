class_name EventPromote extends EventTargetUnit

## Promote ordnance: grants one veterancy level to a clicked friendly unit (any
## type), capped at HEROIC.

func execute(manager: ScenarioTriggerManager) -> void:
	var target: Commandable = _find_target_unit(manager)
	if target == null:
		return
	target.veterancy.promote()
