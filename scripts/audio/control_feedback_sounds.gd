class_name ControlFeedbackSounds

#region Constants
enum LineType {
	SELECTED,
	ISSUED_COMMAND,
	ISSUED_ATTACK
}

const _ROAR := preload("res://assets/audio/didgeridoo-monster-roar.mp3")
const _HOOT := preload("res://assets/audio/hoot.wav")

static var lines: Dictionary = {
	# Fallback voice lines, played for any entity whose type has no entry of its own
	# (and for UNDEFINED-typed entities). _validate() skips UNDEFINED, so this entry
	# is optional to the validation but lets the player always have something to play.
	Entity.Type.UNDEFINED: {
		LineType.SELECTED: [_HOOT],
		LineType.ISSUED_COMMAND: [_HOOT],
		LineType.ISSUED_ATTACK: [_ROAR],
	},
	Entity.Type.AN_UNIT_TECHNICIAN: {
		LineType.SELECTED: [_HOOT],
		LineType.ISSUED_COMMAND: [_ROAR],
		LineType.ISSUED_ATTACK: [_ROAR],
	},
	Entity.Type.AN_UNIT_IRREGULAR: {
		LineType.SELECTED: [_ROAR],
		LineType.ISSUED_COMMAND: [_HOOT],
		LineType.ISSUED_ATTACK: [_ROAR],
	},
	Entity.Type.TC_UNIT_VANGUARD: {
		LineType.SELECTED: [_HOOT],
		LineType.ISSUED_COMMAND: [_ROAR],
		LineType.ISSUED_ATTACK: [_ROAR],
	},
	Entity.Type.AN_UNIT_WARLORD: {
		LineType.SELECTED: [_ROAR],
		LineType.ISSUED_COMMAND: [_ROAR],
		LineType.ISSUED_ATTACK: [_ROAR],
	},
	Entity.Type.AN_UNIT_KAMIKAZE: {
		LineType.SELECTED: [_HOOT],
		LineType.ISSUED_COMMAND: [_HOOT],
		LineType.ISSUED_ATTACK: [_ROAR],
	},
	Entity.Type.CL_UNIT_RECRUIT: {
		LineType.SELECTED: [_HOOT],
		LineType.ISSUED_COMMAND: [_HOOT],
		LineType.ISSUED_ATTACK: [_ROAR],
	},
	Entity.Type.CL_UNIT_BADGER: {
		LineType.SELECTED: [_ROAR],
		LineType.ISSUED_COMMAND: [_HOOT],
		LineType.ISSUED_ATTACK: [_ROAR],
	},
	Entity.Type.TC_STRUCTURE_OUTPOST: {
		LineType.SELECTED: [_ROAR],
		LineType.ISSUED_COMMAND: [_HOOT],
		LineType.ISSUED_ATTACK: [_ROAR],
	},
	Entity.Type.TC_STRUCTURE_DWELLING: {
		LineType.SELECTED: [_HOOT],
		LineType.ISSUED_COMMAND: [_ROAR],
		LineType.ISSUED_ATTACK: [_ROAR],
	},
	Entity.Type.NT_STRUCTURE_MINE: {
		LineType.SELECTED: [_ROAR],
		LineType.ISSUED_COMMAND: [_HOOT],
		LineType.ISSUED_ATTACK: [_ROAR],
	},
	Entity.Type.TC_STRUCTURE_LAB: {
		LineType.SELECTED: [_HOOT],
		LineType.ISSUED_COMMAND: [_ROAR],
		LineType.ISSUED_ATTACK: [_ROAR],
	},
	Entity.Type.TC_STRUCTURE_COMPOUND: {
		LineType.SELECTED: [_ROAR],
		LineType.ISSUED_COMMAND: [_HOOT],
		LineType.ISSUED_ATTACK: [_ROAR],
	},
	Entity.Type.TC_STRUCTURE_ARMORY: {
		LineType.SELECTED: [_HOOT],
		LineType.ISSUED_COMMAND: [_ROAR],
		LineType.ISSUED_ATTACK: [_ROAR],
	},
	Entity.Type.CL_STRUCTURE_CANNON: {
		LineType.SELECTED: [_ROAR],
		LineType.ISSUED_COMMAND: [_HOOT],
		LineType.ISSUED_ATTACK: [_ROAR],
	},
	Entity.Type.CL_STRUCTURE_SAM: {
		LineType.SELECTED: [_ROAR],
		LineType.ISSUED_COMMAND: [_HOOT],
		LineType.ISSUED_ATTACK: [_ROAR],
	},
	Entity.Type.NT_STRUCTURE_DEPOSIT: {
		LineType.SELECTED: [_HOOT],
		LineType.ISSUED_COMMAND: [_ROAR],
		LineType.ISSUED_ATTACK: [_ROAR],
	},
	Entity.Type.NT_STRUCTURE_SHELTER: {
		LineType.SELECTED: [_HOOT],
		LineType.ISSUED_COMMAND: [_ROAR],
		LineType.ISSUED_ATTACK: [_ROAR],
	},
	Entity.Type.AN_STRUCTURE_STRONGHOLD: {
		LineType.SELECTED: [_HOOT],
		LineType.ISSUED_COMMAND: [_ROAR],
		LineType.ISSUED_ATTACK: [_ROAR],
	},
}
#endregion

#region Lifecycle
static func _static_init() -> void:
	_validate()
#endregion

#region Private helpers
static func _validate() -> void:
	for entity_type: Entity.Type in Entity.Type.values():
		if entity_type < 0:
			continue
		if not lines.has(entity_type):
			push_error("ControlFeedbackSounds: missing entry for Entity.Type.%s" % Entity.Type.find_key(entity_type))
			continue
		var type_lines: Dictionary = lines[entity_type]
		for line_type: LineType in LineType.values():
			assert(type_lines.has(line_type),
					"ControlFeedbackSounds: Entity.Type.%s missing LineType.%s" % [
						Entity.Type.find_key(entity_type), LineType.find_key(line_type)])
			assert((type_lines[line_type] as Array).size() > 0,
					"ControlFeedbackSounds: Entity.Type.%s LineType.%s has empty audio list" % [
						Entity.Type.find_key(entity_type), LineType.find_key(line_type)])
#endregion
