class_name EventAbilityAmbush extends AbstractEvent

## Spawns 3 irregulars for the player commander at this event's global_position.
## Intended to be instantiated and positioned at runtime by CommanderAbilityAmbush.

const _IRREGULAR_SCENE: PackedScene = preload("res://scenes/units/irregular.tscn")
const _SPAWN_COUNT: int = 3
const _COMMANDER_ID: int = 1

func execute(manager: ScenarioTriggerManager) -> void:
	var commander: Commander = manager.get_commander(_COMMANDER_ID)
	var map: Map = manager.map
	if commander == null or map == null:
		return

	var spawned: Array[Commandable] = []
	for _i: int in range(_SPAWN_COUNT):
		var entity: Node = _IRREGULAR_SCENE.instantiate()
		if entity is Commandable:
			spawned.append(entity as Commandable)
		else:
			entity.queue_free()

	if spawned.is_empty():
		return

	map.add_entities(spawned, VU.inXZ(global_position), commander)
