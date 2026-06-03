class_name EventChainTrigger
extends ScenarioEvent

## Index into ScenarioEventManager.triggers of the trigger to enable or disable.
@export var trigger_index: int = -1
## True to enable the target trigger; false to disable it.
@export var enable: bool = true

func execute(manager: ScenarioEventManager) -> void:
	if trigger_index < 0 or trigger_index >= manager.triggers.size():
		push_warning("EventChainTrigger: trigger_index %d out of range (triggers.size=%d)" % [
			trigger_index, manager.triggers.size()
		])
		return
	manager.triggers[trigger_index].enabled = enable
