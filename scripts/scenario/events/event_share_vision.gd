@tool
class_name EventShareVision
extends AbstractEvent

## Start or stop a commander lending its vision to its allies, from now on: the runtime form of
## PlayerSlot.shares_vision_with_allies. The fog reads it live (Commander.lends_vision_to), so
## the change shows on its next update. Added for prologue mission 1, whose ally shares its
## vision only once the Clippers are down (Alex, 2026-10-26).

## The commander whose vision is lent or withheld.
@export var commander_id: int = 2
## Lend it (on) or withhold it (off).
@export var shares_vision: bool = true


func execute(a_manager: ScenarioTriggerManager) -> void:
	var commander: Commander = a_manager.get_commander(commander_id)
	if commander == null:
		push_error("EventShareVision: there is no commander %d." % commander_id)
		return
	commander.shares_vision_with_allies = shares_vision
