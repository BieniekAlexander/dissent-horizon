class_name ControlFeedbackSounds

#region Constants
enum LineType { SELECTED, ISSUED_COMMAND, ISSUED_ATTACK }

const _SELECT := preload("res://assets/audio/barks/select0.awchacon.wav")
const _ATTACK := preload("res://assets/audio/barks/attack0.otterbahn.wav")
const _MOVE_0 := preload("res://assets/audio/barks/move0.otterbahn.wav")
const _MOVE_1 := preload("res://assets/audio/barks/move1.otterbahn.wav")

## Units only: a structure does not bark on select or command, so it has no voice-lines
## slot at all. A unit with no entry (or a LineType with no clips) is simply silent at
## runtime — the spec importer reports it as an unfilled asset slot (`has_voice_lines`),
## which is the one place a missing line is surfaced. Each unit's lines are written out
## individually (rather than shared off one constant dict) so a future piece can diverge
## without restructuring this file.
static var lines: Dictionary = {
	EntityIds.CL_BIO_LIGHT_ANTI_MECH:
	{
		LineType.SELECTED: [_SELECT],
		LineType.ISSUED_COMMAND: [_MOVE_0, _MOVE_1],
		LineType.ISSUED_ATTACK: [_ATTACK],
	},
	EntityIds.LB_AIRCRAFT_LIGHT_BUILDER:
	{
		LineType.SELECTED: [_SELECT],
		LineType.ISSUED_COMMAND: [_MOVE_0, _MOVE_1],
		LineType.ISSUED_ATTACK: [_ATTACK],
	},
	EntityIds.AN_AIRCRAFT_LIGHT_TRANSPORT:
	{
		LineType.SELECTED: [_SELECT],
		LineType.ISSUED_COMMAND: [_MOVE_0, _MOVE_1],
		LineType.ISSUED_ATTACK: [_ATTACK],
	},
	EntityIds.AN_MECH_STRONG_TRANSPORT:
	{
		LineType.SELECTED: [_SELECT],
		LineType.ISSUED_COMMAND: [_MOVE_0, _MOVE_1],
		LineType.ISSUED_ATTACK: [_ATTACK],
	},
	EntityIds.LB_AIRCRAFT_LIGHT_ANTI_MECH:
	{
		LineType.SELECTED: [_SELECT],
		LineType.ISSUED_COMMAND: [_MOVE_0, _MOVE_1],
		LineType.ISSUED_ATTACK: [_ATTACK],
	},
	EntityIds.AN_BIO_LIGHT_BUILDER:
	{
		LineType.SELECTED: [_SELECT],
		LineType.ISSUED_COMMAND: [_MOVE_0, _MOVE_1],
		LineType.ISSUED_ATTACK: [_ATTACK],
	},
	EntityIds.AN_AIRCRAFT_LIGHT_ANTI_MECH:
	{
		LineType.SELECTED: [_SELECT],
		LineType.ISSUED_COMMAND: [_MOVE_0, _MOVE_1],
		LineType.ISSUED_ATTACK: [_ATTACK],
	},
	EntityIds.CL_AIRCRAFT_LIGHT_ANTI_LIGHT:
	{
		LineType.SELECTED: [_SELECT],
		LineType.ISSUED_COMMAND: [_MOVE_0, _MOVE_1],
		LineType.ISSUED_ATTACK: [_ATTACK],
	},
	EntityIds.CL_BIO_LIGHT_ANTI_LIGHT:
	{
		LineType.SELECTED: [_SELECT],
		LineType.ISSUED_COMMAND: [_MOVE_0, _MOVE_1],
		LineType.ISSUED_ATTACK: [_ATTACK],
	},
	EntityIds.AN_BIO_LIGHT_ANTI_STRUCTURE:
	{
		LineType.SELECTED: [_SELECT],
		LineType.ISSUED_COMMAND: [_MOVE_0, _MOVE_1],
		LineType.ISSUED_ATTACK: [_ATTACK],
	},
	EntityIds.LB_AIRCRAFT_MEDIUM_ANTI_BIO:
	{
		LineType.SELECTED: [_SELECT],
		LineType.ISSUED_COMMAND: [_MOVE_0, _MOVE_1],
		LineType.ISSUED_ATTACK: [_ATTACK],
	},
	EntityIds.AN_BIO_LIGHT_ANTI_BIO:
	{
		LineType.SELECTED: [_SELECT],
		LineType.ISSUED_COMMAND: [_MOVE_0, _MOVE_1],
		LineType.ISSUED_ATTACK: [_ATTACK],
	},
	EntityIds.CL_BIO_LIGHT_BUILDER:
	{
		LineType.SELECTED: [_SELECT],
		LineType.ISSUED_COMMAND: [_MOVE_0, _MOVE_1],
		LineType.ISSUED_ATTACK: [_ATTACK],
	},
	EntityIds.CL_MECH_LIGHT_DOMINION_GEN:
	{
		LineType.SELECTED: [_SELECT],
		LineType.ISSUED_COMMAND: [_MOVE_0, _MOVE_1],
		LineType.ISSUED_ATTACK: [_ATTACK],
	},
	EntityIds.TC_BIO_LIGHT_BUILDER:
	{
		LineType.SELECTED: [_SELECT],
		LineType.ISSUED_COMMAND: [_MOVE_0, _MOVE_1],
		LineType.ISSUED_ATTACK: [_ATTACK],
	},
	EntityIds.NT_BIO_LIGHT_TERRESTRIAL:
	{
		LineType.SELECTED: [_SELECT],
		LineType.ISSUED_COMMAND: [_MOVE_0, _MOVE_1],
		LineType.ISSUED_ATTACK: [_ATTACK],
	},
	EntityIds.TC_BIO_LIGHT_ANTI_MECH:
	{
		LineType.SELECTED: [_SELECT],
		LineType.ISSUED_COMMAND: [_MOVE_0, _MOVE_1],
		LineType.ISSUED_ATTACK: [_ATTACK],
	},
	EntityIds.AN_BIO_MEDIUM_DOMINION_GEN:
	{
		LineType.SELECTED: [_SELECT],
		LineType.ISSUED_COMMAND: [_MOVE_0, _MOVE_1],
		LineType.ISSUED_ATTACK: [_ATTACK],
	},
	EntityIds.CL_MECH_MEDIUM_ANTI_MECH:
	{
		LineType.SELECTED: [_SELECT],
		LineType.ISSUED_COMMAND: [_MOVE_0, _MOVE_1],
		LineType.ISSUED_ATTACK: [_ATTACK],
	},
	EntityIds.CL_MECH_STRONG_SUPPORT:
	{
		LineType.SELECTED: [_SELECT],
		LineType.ISSUED_COMMAND: [_MOVE_0, _MOVE_1],
		LineType.ISSUED_ATTACK: [_ATTACK],
	},
}
#endregion


#region Public interface
## The LineType names `entity_id` has no clip for — every one when it has no entry. Empty
## means the unit's voice-lines slot is filled. Asked by the spec importer, never at runtime.
static func missing_line_types(entity_id: StringName) -> Array[String]:
	var type_lines: Dictionary = lines.get(entity_id, {})
	var missing: Array[String] = []
	for line_type: LineType in LineType.values():
		if (type_lines.get(line_type, []) as Array).is_empty():
			missing.append(str(LineType.find_key(line_type)))
	return missing
#endregion
