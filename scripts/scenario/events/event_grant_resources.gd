@tool
class_name EventGrantResources
extends AbstractEvent

#region Properties
@export var commander_id: int = 1
@export var ore: int = 0
@export var dominion: int = 0
#endregion

#region Public API
func execute(manager: ScenarioTriggerManager) -> void:
	var commander := manager.get_commander(commander_id)
	if commander == null:
		return
	commander.add_ore(ore)
	commander.add_dominion(dominion)
#endregion
