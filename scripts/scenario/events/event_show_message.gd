@tool
class_name EventShowMessage
extends AbstractEvent

#region Properties
@export_multiline var message: String = ""
#endregion

#region Public API
func execute(manager: ScenarioTriggerManager) -> void:
	manager.message_requested.emit(message)
#endregion
