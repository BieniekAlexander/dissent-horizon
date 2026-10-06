@tool
class_name EventGunship extends AbstractEvent

## Calls a gunship over the target point, from off the map.
##
## The gunship enters over the perimeter nearest the CASTER (OffMapArrival), as the Drop's
## transport does, and flies a [Sortie]: guns cold on the way in, on station over the point for
## `station_seconds`, then home the way it came. This event only launches it.
## Rules: gdd/systems/macroeconomics/sanctions/off-map-abilities.md §Gunship.

#region Properties
## The aircraft sent. Scene-authored, like EventAirDrop's transport.
@export var gunship_scene: PackedScene

## How long it holds station over the point, in seconds.
@export var station_seconds: float = 20.0

## Commander the gunship belongs to. Set by the activating Sanction before execute.
var commander_id: int = 1

## The building that called it in; decides which edge it comes over. Null falls back to the
## target point, as in EventAirDrop.
var caster: Commandable = null

## Memoized: answering means instantiating the whole gunship scene, and the aiming circle asks
## every frame the sanction is armed.
var _area_radius: float = -1.0
#endregion


#region Public API
## The gunship's reach from the centre of its orbit — the ground it can fire on while on station,
## so the aiming circle shows exactly that. The widest ground reach among its weapons, read off
## the scene's range shapes.
func area_radius() -> float:
	if _area_radius < 0.0 and gunship_scene != null:
		_area_radius = _ground_reach_of(gunship_scene)
	return _area_radius


static func _ground_reach_of(scene: PackedScene) -> float:
	var piece: Node = scene.instantiate()
	var reach: float = -1.0
	var loadout: Node = piece.get_node_or_null("Loadout")
	if loadout != null:
		for weapon: Weapon in loadout.get_children().filter(
			func(n: Node) -> bool: return n is Weapon
		):
			var node: CollisionShape3D = weapon.range_node(false)
			if node != null and node.shape != null:
				reach = maxf(reach, RangeShapes.radius_of(node.shape) * node.scale.x)
	piece.free()
	return reach


func execute(a_manager: ScenarioTriggerManager) -> void:
	var commander: Commander = a_manager.get_commander(commander_id)
	var map: Map = a_manager.map
	if commander == null or map == null or gunship_scene == null:
		return
	var station_xz: Vector2 = VU.in_xz(global_position)
	var anchor_xz: Vector2 = VU.in_xz(caster.global_position) if caster != null else station_xz
	var entry_xz: Vector2 = OffMapArrival.entry_xz(map, anchor_xz)

	var gunship: Commandable = gunship_scene.instantiate() as Commandable
	if gunship == null:
		return
	gunship.initialize(map, commander)
	var entry := Vector3(
		entry_xz.x, map.terrain_height_at(entry_xz) + gunship.height_offset(), entry_xz.y
	)
	gunship.global_position = entry
	# Pointed down the run-in at spawn, for EventAirDrop._launch_transport's reason: it arrives
	# at cruise speed with a finite turn rate.
	var run_in: Vector2 = station_xz - entry_xz
	if not run_in.is_zero_approx():
		gunship.rotation.y = atan2(run_in.x, run_in.y)
	var station := Vector3(station_xz.x, map.terrain_height_at(station_xz), station_xz.y)
	Sortie.launch(gunship, map, entry, station, station_seconds)
#endregion
