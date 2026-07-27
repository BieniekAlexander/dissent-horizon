@tool
class_name EventRevealRegion
extends AbstractEvent

## Opens up a piece of the map: at this event's position, or over every node in a group.
##
## Two ways to open it, and the difference is the whole reason for the flag. `clears_fog` off
## marks the ground EXPLORED — the terrain is drawn, but fog.gd only shows an entity whose fog
## pixel is FULLY clear, so anything standing there stays hidden. `clears_fog` on instead
## places a standing vision source, which is what it takes to actually show the player what is
## there. Revealing an objective wants the latter; sketching in a piece of map the player has
## merely heard about wants the former.
##
## The vision source is a Scout: an invisible, unselectable, collision-free entity whose
## VisionRange cylinder clears fog for its owner exactly as a unit's does. Spawned directly
## (initialize → position) rather than through Map.add_entity, whose unit-placement path
## samples a collision radius the Scout deliberately hasn't got — the same reason
## EventRadarScan spawns its own.

#region Constants
const _SCOUT_SCENE: PackedScene = preload("res://scenes/entities/nt_aircraftLight_recon.tscn")
#endregion

#region Properties
## Radius of the opened circle, in world units (the same units as Map.CELL_SIZE).
@export var radius: float = 5.0

## Remove the fog rather than only marking the ground explored.
##
## Off (the default) is the cheap, instantaneous version: the terrain stops being shrouded,
## nothing else changes, and no node is created. On places a persistent vision source, so
## whatever is standing in the circle becomes visible too — and stays visible.
@export var clears_fog: bool = false:
	set(value):
		clears_fog = value
		notify_property_list_changed()

## Whose map this opens up. The cleared fog is only visible to that commander, so a mission
## reveal is the human player's.
@export var commander_id: int = 1

## Open a circle over every Node3D in this group, one each. Empty opens a single circle at
## this event's own position instead.
##
## A group rather than a list of node references because the set is usually a category the
## scene already names — "the camps still standing" — and reading it at fire time means a
## member added, moved or removed later needs no change here.
@export var target_group: StringName = &""

## Seconds the cleared fog lasts; negative is forever (see Lifespan.attach).
## Only meaningful with `clears_fog` on — marking ground explored is permanent by nature.
@export var lifespan_seconds: float = -1.0
#endregion

#region Tool
func _validate_property(a_property: Dictionary) -> void:
	if a_property.name == "lifespan_seconds" and not clears_fog:
		# Nothing persists in the explored-only mode, so a duration would be a lie.
		a_property.usage |= PROPERTY_USAGE_READ_ONLY
#endregion

#region Public API
func execute(a_manager: ScenarioTriggerManager) -> void:
	var points: Array[Vector2] = _target_points(a_manager)
	if points.is_empty():
		return
	if clears_fog:
		_clear_fog_at(points, a_manager)
	else:
		_mark_explored_at(points, a_manager)
#endregion

#region Internal
## Where to open up: every Node3D in `target_group`, or this event's own position when no
## group is named.
func _target_points(a_manager: ScenarioTriggerManager) -> Array[Vector2]:
	var points: Array[Vector2] = []
	if target_group.is_empty():
		points.append(VU.inXZ(global_position))
		return points
	for node: Node in a_manager.get_tree().get_nodes_in_group(target_group):
		var spatial := node as Node3D
		if spatial != null:
			points.append(VU.inXZ(spatial.global_position))
	return points


## Instantaneous: stamp the circles into the fog's explored layer and leave nothing behind.
func _mark_explored_at(a_points: Array[Vector2], a_manager: ScenarioTriggerManager) -> void:
	var fog: Node = a_manager.get_fog()
	if fog == null:
		return
	for point: Vector2 in a_points:
		fog.reveal_region(point, radius)


## Persistent: one Scout per circle, sized to `radius`.
func _clear_fog_at(a_points: Array[Vector2], a_manager: ScenarioTriggerManager) -> void:
	var commander: Commander = a_manager.get_commander(commander_id)
	var map: Map = a_manager.map
	if commander == null or map == null:
		return
	for point: Vector2 in a_points:
		var scout := _SCOUT_SCENE.instantiate() as Commandable
		if scout == null:
			continue
		Lifespan.attach(scout, lifespan_seconds)
		_resize_vision(scout)
		scout.initialize(map, commander)
		scout.global_position = Vector3(point.x, map.terrain_height_at(point), point.y)


## Widen a Scout's VisionRange to `radius`.
##
## The shape is DUPLICATED first: a PackedScene's sub-resources are shared across every
## instance of it, so writing the radius in place would resize the Radar Scan sanction's
## scouts — and each other reveal — along with this one.
func _resize_vision(a_scout: Commandable) -> void:
	var vision := a_scout.get_node_or_null("VisionRange") as CollisionShape3D
	if vision == null or vision.shape == null:
		return
	vision.shape = vision.shape.duplicate()
	var cylinder := vision.shape as CylinderShape3D
	if cylinder != null:
		cylinder.radius = radius
#endregion
