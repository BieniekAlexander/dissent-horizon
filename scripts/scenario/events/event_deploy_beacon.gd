@tool
class_name EventDeployBeacon extends AbstractEvent

## The Colonial Beacon Drop sanction: places a [Beacon] on the ground at the clicked point,
## giving the commander's Bombards a firing solution somewhere no spotter could safely walk.
##
## The beacon it drops is the SAME entity a Spotter calls in, which is the point: the
## Bombard never has to know how a solution was made. What the sanction buys over walking
## a Recruit over is reach and safety; what it costs is dominion and a cooldown.
##
## It is always a POINT beacon, never one riding on a unit — tagging a unit is Spot's alone.
## It has no lifespan and no sight: it stands until a shell spends it or an enemy repairs it
## away, and once the player's own vision leaves it, it marks blind ground.

## Commander the beacon belongs to — whose Bombards may spend it. Set by the activating
## Sanction before execute.
var commander_id: int = 1


func execute(a_manager: ScenarioTriggerManager) -> void:
	var commander: Commander = a_manager.get_commander(commander_id)
	var map: Map = a_manager.map
	if commander == null or map == null:
		return
	var beacon: Entity = Beacon.SCENE.instantiate() as Entity
	beacon.initialize(map, commander)
	var xz: Vector2 = VU.in_xz(global_position)
	beacon.global_position = Vector3(xz.x, map.terrain_height_at(xz), xz.y)
