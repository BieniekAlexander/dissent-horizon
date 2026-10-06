@tool
class_name EventPlaceEmission extends AbstractEvent

## Stand an emission on the target point, owned by the casting commander: an ordnance whose
## whole effect is one piece put into the world there (the Colonial Blizzard). Placed at the
## point and launched at it, so its phases run where it stands.

## The emission to place.
@export var emission_scene: PackedScene

## Commander the emission belongs to. Set by the activating Sanction before execute.
var commander_id: int = 1


func execute(a_manager: ScenarioTriggerManager) -> void:
	var commander: Commander = a_manager.get_commander(commander_id)
	var map: Map = a_manager.map
	if commander == null or map == null or emission_scene == null:
		return
	var xz: Vector2 = VU.in_xz(global_position)
	var point: Vector3 = Vector3(xz.x, map.terrain_height_at(xz), xz.y)
	var emission: Entity = emission_scene.instantiate() as Entity
	emission.initialize(map, commander)
	emission.global_position = point
	Emitter.launch(emission, null, point)
