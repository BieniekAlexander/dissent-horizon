class_name ControlFeedbackSoundPlayer
extends Node

#region Properties
static var _COMMAND_LINE_TYPES: Dictionary[Script, ControlFeedbackSounds.LineType] = {
	Command: ControlFeedbackSounds.LineType.ISSUED_COMMAND,
	Attack: ControlFeedbackSounds.LineType.ISSUED_ATTACK,
}

@onready var _audio: AudioStreamPlayer = $AudioStreamPlayer
#endregion

#region Lifecycle
func _ready() -> void:
	var controller := get_parent().find_child("Controller") as RTSController
	controller.unit_selected.connect(_on_unit_selected)
	controller.command_issued.connect(_on_command_issued)
#endregion

#region Private helpers
func _on_unit_selected(entity: Entity) -> void:
	_play(entity, ControlFeedbackSounds.LineType.SELECTED)

func _on_command_issued(entity: Entity, command_type: Script) -> void:
	if not _COMMAND_LINE_TYPES.has(command_type):
		return
	_play(entity, _COMMAND_LINE_TYPES[command_type])

func _play(entity: Entity, line_type: ControlFeedbackSounds.LineType) -> void:
	if entity.type == Entity.Type.UNDEFINED:
		return
	var type_lines: Dictionary = ControlFeedbackSounds.lines.get(entity.type, {})
	var clips: Array = type_lines.get(line_type, [])
	if clips.is_empty():
		return
	_audio.stream = clips.pick_random()
	_audio.play()
#endregion
