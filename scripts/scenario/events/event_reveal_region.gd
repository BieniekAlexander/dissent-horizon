@tool
class_name EventRevealRegion
extends AbstractEvent

#region Properties
## World-space radius to reveal (in the same units as Map.CELL_SIZE). The centre
## is this node's global_position.
@export var radius: float = 5.0
#endregion

#region Public API
func execute(manager: ScenarioTriggerManager) -> void:
	var fog := manager.get_fog()
	if fog == null:
		return
	fog.reveal_region(VU.inXZ(global_position), radius)
#endregion
