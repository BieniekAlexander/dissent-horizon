@tool
class_name EventChainTrigger
extends AbstractEvent

#region Properties
## The GlobalTrigger to enable or disable when this event fires.
@export var target_event: GlobalTrigger
## True to enable the target event; false to disable it.
@export var enable: bool = true
#endregion

#region Public API
func execute(manager: ScenarioTriggerManager) -> void:
	if target_event == null:
		push_warning("EventChainTrigger: target_event is not set")
		return
	# set_active arms a re-enabled trigger / disarms a disabled one (push model), rather
	# than just flipping a flag the old poll loop would have noticed.
	target_event.set_active(enable, manager)
#endregion
