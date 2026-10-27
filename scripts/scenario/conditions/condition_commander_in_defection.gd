@tool
class_name ConditionCommanderInDefection
extends Condition

## True while a commander is in defection (Commander.is_in_defection): its infrastructure
## upkeep exceeds what it is supplied, so its structures are defective. "The player has cut the
## base's power" — added for prologue mission 1 (Alex, 2026-10-21), whose allied relief force
## flies in the moment the enemy goes defective.
## Rules: gdd/systems/macroeconomics/production-and-economy.md §Defection.
##
## A PULL condition, re-evaluated every poll: defection is a level, and a commander can climb
## back out of it.

@export var commander_id: int = 2


#region Public API
func evaluate(a_manager: ScenarioTriggerManager) -> bool:
	var commander: Commander = a_manager.get_commander(commander_id)
	return commander != null and commander.is_in_defection()
#endregion
