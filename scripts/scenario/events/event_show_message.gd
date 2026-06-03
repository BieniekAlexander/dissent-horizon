class_name EventShowMessage
extends ScenarioEvent

@export_multiline var message: String = ""

func execute(manager: ScenarioEventManager) -> void:
	manager.message_requested.emit(message)
