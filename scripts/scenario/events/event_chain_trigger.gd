@tool
class_name EventChainTrigger
extends ScenarioEvent

#region Properties
## The trigger to enable or disable when this event fires.
@export var target_trigger: Trigger
## True to enable the target trigger; false to disable it.
@export var enable: bool = true
#endregion

#region Public API
func execute(_manager: ScenarioEventManager) -> void:
	if target_trigger == null:
		push_warning("EventChainTrigger: target_trigger is not set")
		return
	target_trigger.enabled = enable
#endregion
