class_name EventRadarScan extends AbstractEvent

## Radar Scan ordnance: spawns an invisible, commander-owned Scout at the clicked
## position. The Scout's VisionRange reveals the fog around it for its (short)
## lifespan, then it removes itself — a temporary reveal of a portion of the map.

const _SCOUT_SCENE: PackedScene = preload("res://scenes/entities/scout.tscn")

## Commander the revealed vision belongs to. Set by the activating Ordnance before
## execute, so the same event serves the human player and any bot.
var commander_id: int = 1

func execute(manager: ScenarioTriggerManager) -> void:
	var commander: Commander = manager.get_commander(commander_id)
	var map: Map = manager.map
	if commander == null or map == null:
		return

	var scout := _SCOUT_SCENE.instantiate() as Scout
	if scout == null:
		return
	# Spawn directly (initialize → add to commander) rather than via map.add_entity,
	# whose unit-placement path samples the entity's collision radius — the Scout has
	# no collision shape. This mirrors how EventAbilityIrradiate spawns its projectile.
	scout.initialize(map, commander)
	var xz: Vector2 = VU.inXZ(global_position)
	scout.global_position = Vector3(xz.x, map.terrain_height_at(xz), xz.y)
