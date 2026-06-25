class_name EventAbilityIrradiate extends AbstractEvent

## Spawns a radiation projectile near the clicked position so it lands immediately.
## The source is offset 0.5 units along +X so the short ballistic arc resolves
## within a few physics frames and the field appears right at the target.

const _RADIATION_SCENE: PackedScene = preload("res://scenes/entities/projectiles/radiation.tscn")
const _SOURCE_OFFSET: float = 0.5
const _COMMANDER_ID: int = 1

func execute(manager: ScenarioTriggerManager) -> void:
	var commander: Commander = manager.get_commander(_COMMANDER_ID)
	var map: Map = manager.map
	if commander == null or map == null:
		return

	var target_pos: Vector3 = global_position
	target_pos.y = map.terrain_height_at(VU.inXZ(target_pos))
	var source_pos: Vector3 = target_pos + Vector3(_SOURCE_OFFSET, 0.0, 0.0)

	var projectile: Projectile = _RADIATION_SCENE.instantiate() as Projectile
	projectile.initialize(map, commander)
	projectile.global_position = source_pos
	projectile.initialize_projectile(null, target_pos)
