class_name EventWinLose
extends ScenarioEvent

## True → player wins; false → player loses.
@export var player_wins: bool = true

func execute(manager: ScenarioEventManager) -> void:
	manager.game_over.emit(player_wins)
