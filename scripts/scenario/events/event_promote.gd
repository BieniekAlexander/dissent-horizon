@tool
class_name EventPromote extends EventTargetUnit

## Promotion sanction (Colonial tier 0): grants the first veterancy level to a clicked
## friendly unit of any type.
##
## Only a unit with NO veterancy yet qualifies (gdd/factions/colonial/colonial.md:
## "The only valid targets shall be the ones that are still with no veterancy levels").
## So it is a way to START a unit's career, never a shortcut to Heroic — the later
## levels stay earned in combat, and the sanction cannot be stacked on one favourite.
## A unit that has already earned a level is simply not a candidate, so a click near a
## mixed group picks the nearest UNBLOODED unit rather than being refused.

func _qualifies(a_candidate: Commandable) -> bool:
	return a_candidate.veterancy != null and a_candidate.veterancy.level == Veterancy.Level.NONE

func execute(a_manager: ScenarioTriggerManager) -> void:
	var target: Commandable = _find_target_unit(a_manager)
	if target == null:
		return
	target.veterancy.promote()
