@tool
class_name EventAirDrop extends AbstractEvent

## Delivers units to the target point BY AIR, from off the map.
##
## The pieces are not conjured where they are wanted: a transport enters over the perimeter
## nearest the CASTER (see OffMapArrival), flies to the target with the shipment in its
## hold, tips it out under canopy, and carries on along the same line until it is off the
## board again. The whole flight is one AirDropRun order on the transport; this event only
## sets it up.
##
## The shipment rides in a GARRISON rather than in a list this event keeps. That is what an
## entity carrying other entities already is, and it buys the whole delivery for free —
## occupants leave the tree (so they are invisible, unshootable and unpathed in transit),
## they come back under their own commander, and Garrison's release placement spreads them
## onto free ground around the drop point. The one thing added on top is the canopy, which
## AirDropRun hangs on each unit before releasing it.
##
## All three Drop tiers are THIS ONE EVENT with a different `entity_scenes`, exactly as
## they were when the drop was an instant spawn: a tier is authored data.

#region Properties
## The pieces to deliver. Each is instanced `count` times, matching EventSpawnEntities.
@export var entity_scenes: Array[PackedScene] = []

## How many of EACH scene to deliver.
##
## A plain int rather than EventSpawnEntities' expression, because a delivery is bounded by
## the transport's hold in a way a ground spawn is not: an expression that grew with the
## trigger's fire count would silently overflow `Garrison.capacity` and drop part of the
## shipment on the tarmac. A tier that wants more units gets a bigger transport.
@export var count: int = 1

## The aircraft that brings them. Scene-authored: it is a scene reference, and which
## airframe a faction sends is a flavour decision, not a number.
@export var transport_scene: PackedScene

## Commander the transport and its shipment belong to. Set by the activating Sanction
## before execute, so the same event serves the player and any bot.
var commander_id: int = 1

## The building that called it in — its position decides which edge the transport comes
## over. Null falls back to the drop point itself, which still brings the transport in
## from off the map, just from the nearest edge to the target rather than to the caster.
var caster: Commandable = null
#endregion


#region Public API
func execute(a_manager: ScenarioTriggerManager) -> void:
	var commander: Commander = a_manager.get_commander(commander_id)
	var map: Map = a_manager.map
	if commander == null or map == null or transport_scene == null:
		return

	var drop_xz: Vector2 = VU.in_xz(global_position)
	var anchor_xz: Vector2 = VU.in_xz(caster.global_position) if caster != null else drop_xz
	var entry_xz: Vector2 = OffMapArrival.entry_xz(map, anchor_xz)

	var transport: Commandable = _launch_transport(map, commander, entry_xz, drop_xz)
	if transport == null:
		return
	_load_cargo(transport, map, commander)

	var drop_point := Vector3(drop_xz.x, map.terrain_height_at(drop_xz), drop_xz.y)
	transport.update_commands(AirDropRun.new(CommandMessage.new(map, null, null, drop_point)))


#endregion


#region Private helpers
## Put the transport in the air at `entry_xz`, already pointed at the drop.
##
## Spawned through initialize() rather than Map.add_entities, which spreads a group onto
## free NAVMESH around a point: the entry position is deliberately off the map, where there
## is none, and an aircraft has no business being placed against the ground anyway.
##
## It is aimed by hand at spawn because it arrives at cruise speed with a finite turn rate:
## an aircraft that appeared facing an arbitrary direction would fly an entry curve, or a
## full circle, before it got onto the run-in line the player is watching for.
func _launch_transport(
	a_map: Map, a_commander: Commander, a_entry_xz: Vector2, a_drop_xz: Vector2
) -> Commandable:
	var transport: Commandable = transport_scene.instantiate() as Commandable
	if transport == null:
		return null
	transport.initialize(a_map, a_commander)
	var cruise: float = transport.height_offset()
	transport.global_position = Vector3(
		a_entry_xz.x, a_map.terrain_height_at(a_entry_xz) + cruise, a_entry_xz.y
	)
	# Set outright rather than through Movement.face_toward, which turns at the airframe's
	# turn_rate and would take the same second and a half a mid-air heading change does.
	# rotation.y IS the facing (see Movement.get_facing): +Z is the model's front.
	var run_in: Vector2 = a_drop_xz - a_entry_xz
	if not run_in.is_zero_approx():
		transport.rotation.y = atan2(run_in.x, run_in.y)
	return transport


## Fill the transport's hold with the shipment.
##
## Each unit is initialized (so its components resolve and it belongs to the commander)
## before being garrisoned, exactly as EventSpawnEntities' own garrison path does. A hold
## with no room is an AUTHORING error — the tier asked for more than its transport carries
## — so it is reported rather than silently short-shipped, and the surplus is freed rather
## than left orphaned off-tree.
func _load_cargo(a_transport: Commandable, a_map: Map, a_commander: Commander) -> void:
	var hold: Garrison = a_transport.get_node_or_null("Garrison") as Garrison
	if hold == null:
		push_error(
			(
				"EventAirDrop '%s': transport '%s' has no Garrison to carry the drop"
				% [name, a_transport.name]
			)
		)
		return
	for packed: PackedScene in entity_scenes:
		if packed == null:
			continue
		for _i: int in maxi(count, 0):
			var unit: Commandable = packed.instantiate() as Commandable
			if unit == null:
				continue
			unit.initialize(a_map, a_commander)
			if not hold.has_room_for(unit):
				push_error(
					(
						"EventAirDrop '%s': transport hold is full — '%s' left behind"
						% [name, unit.name]
					)
				)
				unit.queue_free()
				continue
			hold.garrison(unit)
#endregion
