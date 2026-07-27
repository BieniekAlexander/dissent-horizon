class_name EventAbilityIrradiate extends AbstractEvent

## Spawns a radiation projectile near the clicked position so it lands immediately.
## The source is offset 0.5 units along +X so the short ballistic arc resolves
## within a few physics frames and the field appears right at the target.

const _RADIATION_SCENE: PackedScene = preload("res://scenes/entities/projectiles/radiation.tscn")
const _SOURCE_OFFSET: float = 0.5

## Commander the radiation field belongs to (whose enemies it damages). Set by the
## activating Sanction before execute, so the same event serves the player or a bot.
var commander_id: int = 1

func execute(a_manager: ScenarioTriggerManager) -> void:
	var commander: Commander = a_manager.get_commander(commander_id)
	var map: Map = a_manager.map
	if commander == null or map == null:
		return

	var target_pos: Vector3 = global_position
	target_pos.y = map.terrain_height_at(VU.inXZ(target_pos))
	var source_pos: Vector3 = target_pos + Vector3(_SOURCE_OFFSET, 0.0, 0.0)

	var projectile: Entity = _RADIATION_SCENE.instantiate() as Entity
	projectile.initialize(map, commander)
	projectile.global_position = source_pos
	Emitter.launch(projectile, null, target_pos)
