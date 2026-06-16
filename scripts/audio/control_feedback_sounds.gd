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
	Entity.Type.UNIT_TECHNICIAN: {
		LineType.SELECTED: [_HOOT],
		LineType.ISSUED_COMMAND: [_ROAR],
		LineType.ISSUED_ATTACK: [_ROAR],
	},
	Entity.Type.UNIT_IRREGULAR: {
		LineType.SELECTED: [_ROAR],
		LineType.ISSUED_COMMAND: [_HOOT],
		LineType.ISSUED_ATTACK: [_ROAR],
	},
	Entity.Type.UNIT_VANGUARD: {
		LineType.SELECTED: [_HOOT],
		LineType.ISSUED_COMMAND: [_ROAR],
		LineType.ISSUED_ATTACK: [_ROAR],
	},
	Entity.Type.UNIT_WARLORD: {
		LineType.SELECTED: [_ROAR],
		LineType.ISSUED_COMMAND: [_ROAR],
		LineType.ISSUED_ATTACK: [_ROAR],
	},
	Entity.Type.STRUCTURE_OUTPOST: {
		LineType.SELECTED: [_ROAR],
		LineType.ISSUED_COMMAND: [_HOOT],
		LineType.ISSUED_ATTACK: [_ROAR],
	},
	Entity.Type.STRUCTURE_DWELLING: {
		LineType.SELECTED: [_HOOT],
		LineType.ISSUED_COMMAND: [_ROAR],
		LineType.ISSUED_ATTACK: [_ROAR],
	},
	Entity.Type.STRUCTURE_MINE: {
		LineType.SELECTED: [_ROAR],
		LineType.ISSUED_COMMAND: [_HOOT],
		LineType.ISSUED_ATTACK: [_ROAR],
	},
	Entity.Type.STRUCTURE_LAB: {
		LineType.SELECTED: [_HOOT],
		LineType.ISSUED_COMMAND: [_ROAR],
		LineType.ISSUED_ATTACK: [_ROAR],
	},
	Entity.Type.STRUCTURE_COMPOUND: {
		LineType.SELECTED: [_ROAR],
		LineType.ISSUED_COMMAND: [_HOOT],
		LineType.ISSUED_ATTACK: [_ROAR],
	},
	Entity.Type.STRUCTURE_ARMORY: {
		LineType.SELECTED: [_HOOT],
		LineType.ISSUED_COMMAND: [_ROAR],
		LineType.ISSUED_ATTACK: [_ROAR],
	},
	Entity.Type.STRUCTURE_TURRET: {
		LineType.SELECTED: [_ROAR],
		LineType.ISSUED_COMMAND: [_HOOT],
		LineType.ISSUED_ATTACK: [_ROAR],
	},
	Entity.Type.STRUCTURE_DEPOSIT: {
		LineType.SELECTED: [_HOOT],
		LineType.ISSUED_COMMAND: [_ROAR],
		LineType.ISSUED_ATTACK: [_ROAR],
	},
	Entity.Type.STRUCTURE_SHELTER: {
		LineType.SELECTED: [_HOOT],
		LineType.ISSUED_COMMAND: [_ROAR],
		LineType.ISSUED_ATTACK: [_ROAR],
	},
	Entity.Type.STRUCTURE_REDOUBT: {
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
		if entity_type == Entity.Type.UNDEFINED:
			continue
		assert(lines.has(entity_type),
				"ControlFeedbackSounds: missing entry for Entity.Type.%s" % Entity.Type.find_key(entity_type))
		var type_lines: Dictionary = lines[entity_type]
		for line_type: LineType in LineType.values():
			assert(type_lines.has(line_type),
					"ControlFeedbackSounds: Entity.Type.%s missing LineType.%s" % [
						Entity.Type.find_key(entity_type), LineType.find_key(line_type)])
			assert((type_lines[line_type] as Array).size() > 0,
					"ControlFeedbackSounds: Entity.Type.%s LineType.%s has empty audio list" % [
						Entity.Type.find_key(entity_type), LineType.find_key(line_type)])
#endregion
