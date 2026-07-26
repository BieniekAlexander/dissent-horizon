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
	# Fallback voice lines, played for any entity whose id has no entry of its own
	# (and for empty-id entities). _validate() skips the fallback, so this entry
	# is optional to the validation but lets the player always have something to play.
	&"": {
		LineType.SELECTED: [_HOOT],
		LineType.ISSUED_COMMAND: [_HOOT],
		LineType.ISSUED_ATTACK: [_ROAR],
	},
	EntityIds.TECHNICIAN: {
		LineType.SELECTED: [_HOOT],
		LineType.ISSUED_COMMAND: [_ROAR],
		LineType.ISSUED_ATTACK: [_ROAR],
	},
	EntityIds.IRREGULAR: {
		LineType.SELECTED: [_ROAR],
		LineType.ISSUED_COMMAND: [_HOOT],
		LineType.ISSUED_ATTACK: [_ROAR],
	},
	EntityIds.VANGUARD: {
		LineType.SELECTED: [_HOOT],
		LineType.ISSUED_COMMAND: [_ROAR],
		LineType.ISSUED_ATTACK: [_ROAR],
	},
	EntityIds.WARLORD: {
		LineType.SELECTED: [_ROAR],
		LineType.ISSUED_COMMAND: [_ROAR],
		LineType.ISSUED_ATTACK: [_ROAR],
	},
	EntityIds.KAMIKAZE: {
		LineType.SELECTED: [_HOOT],
		LineType.ISSUED_COMMAND: [_HOOT],
		LineType.ISSUED_ATTACK: [_ROAR],
	},
	EntityIds.RECRUIT: {
		LineType.SELECTED: [_HOOT],
		LineType.ISSUED_COMMAND: [_HOOT],
		LineType.ISSUED_ATTACK: [_ROAR],
	},
	EntityIds.BADGER: {
		LineType.SELECTED: [_ROAR],
		LineType.ISSUED_COMMAND: [_HOOT],
		LineType.ISSUED_ATTACK: [_ROAR],
	},
	&"outpost": {   # no spec doc yet (scene missing); raw id keeps the lines wired
	
		LineType.SELECTED: [_ROAR],
		LineType.ISSUED_COMMAND: [_HOOT],
		LineType.ISSUED_ATTACK: [_ROAR],
	},
	EntityIds.DWELLING: {
		LineType.SELECTED: [_HOOT],
		LineType.ISSUED_COMMAND: [_ROAR],
		LineType.ISSUED_ATTACK: [_ROAR],
	},
	EntityIds.MINE: {
		LineType.SELECTED: [_ROAR],
		LineType.ISSUED_COMMAND: [_HOOT],
		LineType.ISSUED_ATTACK: [_ROAR],
	},
	EntityIds.LAB: {
		LineType.SELECTED: [_HOOT],
		LineType.ISSUED_COMMAND: [_ROAR],
		LineType.ISSUED_ATTACK: [_ROAR],
	},
	EntityIds.COMPOUND: {
		LineType.SELECTED: [_ROAR],
		LineType.ISSUED_COMMAND: [_HOOT],
		LineType.ISSUED_ATTACK: [_ROAR],
	},
	EntityIds.ARMORY: {
		LineType.SELECTED: [_HOOT],
		LineType.ISSUED_COMMAND: [_ROAR],
		LineType.ISSUED_ATTACK: [_ROAR],
	},
	EntityIds.CANNON: {
		LineType.SELECTED: [_ROAR],
		LineType.ISSUED_COMMAND: [_HOOT],
		LineType.ISSUED_ATTACK: [_ROAR],
	},
	EntityIds.SAM: {
		LineType.SELECTED: [_ROAR],
		LineType.ISSUED_COMMAND: [_HOOT],
		LineType.ISSUED_ATTACK: [_ROAR],
	},
	EntityIds.DEPOSIT: {
		LineType.SELECTED: [_HOOT],
		LineType.ISSUED_COMMAND: [_ROAR],
		LineType.ISSUED_ATTACK: [_ROAR],
	},
	&"shelter": {   # no spec doc yet (root isn't an Entity); raw id keeps the lines wired
	
		LineType.SELECTED: [_HOOT],
		LineType.ISSUED_COMMAND: [_ROAR],
		LineType.ISSUED_ATTACK: [_ROAR],
	},
	EntityIds.STRONGHOLD: {
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
	# Completeness is checked against the generated piece-id registry (EntityIds),
	# so a newly doc'd piece immediately flags its missing voice lines here.
	var piece_ids: Dictionary = (EntityIds as Script).get_script_constant_map()
	for const_name in piece_ids:
		var entity_id: StringName = piece_ids[const_name]
		if not lines.has(entity_id):
			push_error("ControlFeedbackSounds: missing entry for piece '%s'" % entity_id)
			continue
		var type_lines: Dictionary = lines[entity_id]
		for line_type: LineType in LineType.values():
			assert(type_lines.has(line_type),
					"ControlFeedbackSounds: piece '%s' missing LineType.%s" % [
						entity_id, LineType.find_key(line_type)])
			assert((type_lines[line_type] as Array).size() > 0,
					"ControlFeedbackSounds: piece '%s' LineType.%s has empty audio list" % [
						entity_id, LineType.find_key(line_type)])
#endregion
