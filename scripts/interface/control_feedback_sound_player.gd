class_name ControlFeedbackSoundPlayer
extends Node

#region Properties
## Attack and AttackMove are the only command types that bark the ATTACK line;
## every other command a unit is given (move, stop, defend, build, repair, ...)
## barks ISSUED_COMMAND instead. See _on_command_issued.
static var _ATTACK_COMMAND_TYPES: Array[Script] = [Attack, AttackMove]

@onready var _audio: AudioStreamPlayer = $AudioStreamPlayer
## Which clip plays is the interface's own draw, never the simulation's: a line picked from the
## global generator would move a replay off its recording (recording-and-replay.md).
var _rng := RandomNumberGenerator.new()
#endregion


#region Lifecycle
func _ready() -> void:
	# Orders can still be issued while a SimulationClock hold pauses the world, so their
	# audio feedback has to survive the pause too — a paused AudioStreamPlayer is silent.
	process_mode = Node.PROCESS_MODE_ALWAYS
	var controller := get_parent().find_child("Controller") as RTSController
	controller.unit_selected.connect(_on_unit_selected)
	controller.command_issued.connect(_on_command_issued)


#endregion


#region Private helpers
func _on_unit_selected(a_entity: Entity) -> void:
	_play(a_entity, ControlFeedbackSounds.LineType.SELECTED)


func _on_command_issued(a_entity: Entity, a_command_type: Script) -> void:
	var line_type: ControlFeedbackSounds.LineType = (
		ControlFeedbackSounds.LineType.ISSUED_ATTACK
		if a_command_type in _ATTACK_COMMAND_TYPES
		else ControlFeedbackSounds.LineType.ISSUED_COMMAND
	)
	_play(a_entity, line_type)


func _play(a_entity: Entity, a_line_type: ControlFeedbackSounds.LineType) -> void:
	# Structures (and any other entity with no entry) have no lines at all, by
	# design — see ControlFeedbackSounds.lines. No fallback: nothing to play.
	var type_lines: Dictionary = ControlFeedbackSounds.lines.get(a_entity.id, {})
	var clips: Array = type_lines.get(a_line_type, [])
	if clips.is_empty():
		return
	_audio.stream = AU.pick_random(clips, _rng)
	_audio.play()
#endregion
