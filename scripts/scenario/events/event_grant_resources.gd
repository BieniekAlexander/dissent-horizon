@tool
class_name EventGrantResources
extends AbstractEvent

#region Properties
@export var commander_id: int = 1
@export var energy: int = 0
@export var dominion: int = 0
#endregion

#region Public API
func execute(a_manager: ScenarioTriggerManager) -> void:
	var commander := a_manager.get_commander(commander_id)
	if commander == null:
		return
	commander.add_energy(energy)
	commander.add_dominion(dominion)
#endregion
