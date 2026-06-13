@tool
class_name EventGrantResources
extends ScenarioEvent

@export var commander_id: int = 1
@export var ore: int = 0
@export var dominion: int = 0

func execute(manager: ScenarioEventManager) -> void:
	var commander := manager.get_commander(commander_id)
	if commander == null:
		return
	commander.ore += ore
	commander.dominion += dominion
