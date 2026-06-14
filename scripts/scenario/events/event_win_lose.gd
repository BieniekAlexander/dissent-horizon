@tool
class_name EventWinLose
extends ScenarioEvent

#region Properties
## True → player wins; false → player loses.
@export var player_wins: bool = true
#endregion

#region Public API
func execute(manager: ScenarioEventManager) -> void:
	manager.game_over.emit(player_wins)
#endregion
