class_name Veterancy
extends Node

## Tracks a commandable's earned rank and the experience behind it. It owns NO art: the
## chevrons floating over a promoted unit are drawn by StatusVisuals, which reads `level`
## off this component. That split is why the old numeric Label3D is gone — a component
## that counts XP had no business owning a node in the scene, and it could not gate itself
## on the things a floating marker has to be gated on (stealth, blueprints).

enum Level { NONE = 0, VETERAN = 1, ELITE = 2, HEROIC = 3 }

## XP-scaling balance knobs — raise to promote faster veterancy progression.
const XP_PER_DAMAGE: float = 0.05      ## XP per point of damage dealt (ON_DEAL_DAMAGE)
const XP_PER_KILL_HP: float = 0.05     ## XP per point of killed unit's max HP (ON_KILL)
const XP_PER_BUILD_ENERGY: float = 0.05  ## XP per energy cost of a completed structure (ON_FINISH_BUILD)

var experience: int = 0
@export var level: Level = Level.NONE

# TODO: thresholds are one table for every piece, and a rank pays damage only. Both are to be
# calibrated per unit — a rank may grow durability or grant abilities, and the XP to reach it
# should scale with the power it confers. Deferred; see design-framework/elasticity.md §Veterancy.
const _LEVEL_THRESHOLDS: Array[int] = [0, 20, 50, 100]

func _ready() -> void:
	experience = _LEVEL_THRESHOLDS[int(level)]

func gain_experience(a_amount: int) -> void:
	experience += a_amount
	_update_level()

## Set veterancy to exactly `new_level`, syncing `experience` to that level's
## threshold. Used to transfer a rank wholesale (e.g. the Dignify sanction carries an
## Irregular's rank onto the Warlord it becomes).
func set_level(a_new_level: Level) -> void:
	level = a_new_level
	experience = _LEVEL_THRESHOLDS[int(a_new_level)]

## Advance one veterancy level, capped at HEROIC. Used by the Promote sanction.
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
