@tool
class_name EventShowMessage
extends AbstractEvent

#region Properties
@export_multiline var message: String = ""
#endregion

#region Public API
func execute(a_manager: ScenarioTriggerManager) -> void:
	a_manager.message_requested.emit(message)
#endregion
