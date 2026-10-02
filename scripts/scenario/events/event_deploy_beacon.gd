@tool
class_name EventDeployBeacon extends AbstractEvent

## The Colonial Beacon Drop family: places a [Beacon] at the clicked point, giving the
## commander's Bombards a firing solution somewhere no spotter could safely walk.
##
## All three tiers are THIS ONE EVENT with different exports, because the tiers differ
## only in how long the solution stands and whether it can see:
##   Beacon 1 — 15 seconds, blind
##   Beacon 2 — 15 seconds, sight radius 2
##   Beacon 3 — until spent, sight radius 2
##
## The beacon it drops is the SAME entity a Spotter calls in, which is the point: the
## Bombard never has to know how a solution was made. What the sanction buys over walking
## a Recruit over is reach and safety; what it costs is dominion and a cooldown, and — at
## the first two tiers — a clock the spotter's version does not have.
##
## Sight is a VisionRange created HERE rather than shipped disabled on beacon.tscn, so a
## blind beacon genuinely has no vision node and never joins the fog's "los" group. Same
## reasoning as EventRadarScan's detection shape.

## Seconds the beacon stands before expiring. Negative = it stands until a shot spends
## it, which is how Beacon 3 is authored.
@export var lifespan_seconds: float = 15.0

## Fog-clearing radius, in world units. 0 or less = the beacon sees nothing (Beacon 1).
@export var sight_radius: float = 0.0

## Commander the beacon belongs to — whose Bombards may spend it, and whose fog its sight
## clears. Set by the activating Sanction before execute.
var commander_id: int = 1


func execute(a_manager: ScenarioTriggerManager) -> void:
	var commander: Commander = a_manager.get_commander(commander_id)
	var map: Map = a_manager.map
	if commander == null or map == null:
		return
	var beacon: Entity = Beacon.SCENE.instantiate() as Entity
	Lifespan.attach(beacon, lifespan_seconds)
	_add_sight(beacon)
	beacon.initialize(map, commander)
	var xz: Vector2 = VU.inXZ(global_position)
	beacon.global_position = Vector3(xz.x, map.terrain_height_at(xz), xz.y)
	var carrier: Entity = _carrier_near(beacon)
	if carrier != null:
		Beacon.of(beacon).attach_to(carrier)


## The enemy unit a beacon dropped here lands ON: the nearest one within Beacon.ATTACH_RADIUS
## that can carry a beacon (a grounded MECH unit). Null leaves the beacon on the ground.
func _carrier_near(a_beacon: Entity) -> Entity:
	var nearby: Array = SU.get_nearby_entities(
		a_beacon.get_world_3d(),
		a_beacon.global_position,
		Beacon.ATTACH_RADIUS,
		CollisionLayers.TARGETABLE_ANY
	)
	var best: Entity = null
	var best_distance: float = INF
	for candidate: Variant in nearby:
		var entity := candidate as Entity
		if entity == null or not Beacon.can_carry(entity) or not a_beacon.is_enemy_of(entity):
			continue
		var distance: float = entity.xz_position.distance_to(a_beacon.xz_position)
		if distance < best_distance:
			best_distance = distance
			best = entity
	return best


## Give the beacon a VisionRange so Entity._ready puts it in the "los" group and fog.gd
## treats it as a vision source. Attached BEFORE initialize() puts it in the tree, so the
## @onready that seeds Entity.vision_range_shape resolves it.
func _add_sight(a_beacon: Entity) -> void:
	if sight_radius <= 0.0:
		return
	var shape := CylinderShape3D.new()
	shape.radius = sight_radius
	# Tall enough to reach aerial units, matching scout.tscn's own VisionRange.
	shape.height = 100.0
	var node := CollisionShape3D.new()
	node.name = "VisionRange"
	node.shape = shape
	a_beacon.add_child(node)
