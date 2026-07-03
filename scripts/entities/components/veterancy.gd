class_name Veterancy
extends Node

enum Level { NONE = 0, VETERAN = 1, ELITE = 2, HEROIC = 3 }

## XP-scaling balance knobs — raise to promote faster veterancy progression.
const XP_PER_DAMAGE: float = 0.05      ## XP per point of damage dealt (ON_DEAL_DAMAGE)
const XP_PER_KILL_HP: float = 0.05     ## XP per point of killed unit's max HP (ON_KILL)
const XP_PER_BUILD_ORE: float = 0.05  ## XP per ore cost of a completed structure (ON_FINISH_BUILD)

var experience: int = 0
@export var level: Level = Level.NONE

@onready var _label: Label3D = get_parent().find_child("VeterancyLabel")

const _LEVEL_THRESHOLDS: Array[int] = [0, 20, 50, 100]

func _ready() -> void:
	experience = _LEVEL_THRESHOLDS[int(level)]
	_update_label()

func gain_experience(amount: int) -> void:
	experience += amount
	_update_level()

## Set veterancy to exactly `new_level`, syncing `experience` to that level's
## threshold. Used to transfer a rank wholesale (e.g. the Dignify ordnance carries an
## Irregular's rank onto the Warlord it becomes).
func set_level(new_level: Level) -> void:
	level = new_level
	experience = _LEVEL_THRESHOLDS[int(new_level)]
	_update_label()

## Advance one veterancy level, capped at HEROIC. Used by the Promote ordnance.
func promote() -> void:
	if level < Level.HEROIC:
		set_level((int(level) + 1) as Level)

func _update_level() -> void:
	var new_level: Level
	if experience >= 100:
		new_level = Level.HEROIC
	elif experience >= 50:
		new_level = Level.ELITE
	elif experience >= 20:
		new_level = Level.VETERAN
	else:
		new_level = Level.NONE
	if new_level != level:
		level = new_level
		_update_label()

func _update_label() -> void:
	if _label == null:
		return
	if level == Level.NONE:
		_label.visible = false
	else:
		_label.visible = true
		_label.text = str(int(level))
