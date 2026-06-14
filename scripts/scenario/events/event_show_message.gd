@tool
class_name EventShowMessage
extends ScenarioEvent

#region Properties
@export_multiline var message: String = ""
#endregion

#region Public API
func execute(manager: ScenarioEventManager) -> void:
	manager.message_requested.emit(message)
#endregion
