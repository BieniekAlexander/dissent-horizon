class_name AirDropRun
extends MoveCommand

## The delivery run a called-in air transport flies: in from off the map to the drop point,
## cargo out under canopy, then straight on along the same line and off the far side, where
## the transport removes itself.
##
## NOT A PLAYER-FACING COMMAND. Nothing offers it on the command grid and
## CommandContextParser does not know its name — it is issued by EventAirDrop to a piece
## the player never selects, in the same way Wander is issued to pieces nobody orders. It
## is a COMMAND rather than a behaviour script on the transport because the run genuinely
## IS a sequence of orders — fly here, act, fly on — and the receiver already drives that
## shape, including the "a fixed wing does not stop to shoot" handling that keeps the
## aircraft moving through the moment it acts.
##
## ONE command across both legs rather than a queued pair, because the second leg's
## destination is not known until the first one ends: the transport leaves along the
## heading it arrived on, which is a fact about where it actually was when it let go.

#region Constants
## Which half of the run is being flown.
enum Phase {
	## Inbound to the drop point, cargo aboard.
	APPROACH,
	## Outbound along the arrival heading, empty, until clear of the map.
	EGRESS,
}

## How close to the drop point counts as over it, in world units.
##
## Generous, and deliberately: the transport is flying at cruise speed and cannot stop, so
## a tight radius would be crossed inside one physics tick at high speed and missed. The
## cargo is spread onto free ground around the release point anyway (see Garrison.evacuate),
## so a few units of imprecision in where the canopy opens costs nothing.
const DROP_RADIUS: float = 2.0

## The canopy hung over each unit while it descends. A prop with no script and no
## behaviour: it is added at the drop and freed at touchdown, and that is its whole life.
const CANOPY_SCENE: PackedScene = preload("res://scenes/entities/parachute.tscn")
#endregion

#region Properties
var _phase: Phase = Phase.APPROACH
## Where the transport is aimed once the cargo is away. Set at the moment of the drop,
## because it is derived from the heading the transport actually arrived on.
var _egress_point: Vector3 = Vector3.ZERO
#endregion


#region State updates
## Always flying — a transport on a delivery run has no idle state.
func should_move(_a_actor: Commandable) -> bool:
	return true


## The run is not over when the transport reaches the drop point; that is the middle of it.
## Without this the receiver's arrival branch would throw the order away the tick the
## aircraft got there and leave it orbiting over the target with its cargo still aboard.
func ends_on_arrival() -> bool:
	return false


## APPROACH flies to the drop point (message.position, the usual resolution); EGRESS flies
## to the point past the far edge computed when the cargo went out.
func movement_destination(_a_actor: Commandable) -> Variant:
	return _egress_point if _phase == Phase.EGRESS else null


func can_act(a_actor: Commandable) -> bool:
	if _phase == Phase.APPROACH:
		return a_actor.xz_position.distance_to(message.xz_position) <= DROP_RADIUS
	return OffMapArrival.has_left(message.map, a_actor.xz_position)


## APPROACH: release the cargo and turn the run into its outbound leg, keeping the command.
## EGRESS: the transport is off the board — remove it, and end.
func fulfill_action(a_actor: Commandable) -> Variant:
	if _phase == Phase.EGRESS:
		a_actor.queue_free()
		return null
	_release_cargo(a_actor)
	_egress_point = _resolve_egress_point(a_actor)
	_phase = Phase.EGRESS
	return self


#endregion


#region Private helpers
## Tip everything aboard out over the drop point, each under a canopy.
##
## The descent is started BEFORE the evacuation, and that ordering is what makes it work:
## Garrison places each evacuee at terrain height plus its `Movement.height_offset()`, and
## for a unit that has just been put into a parachute descent that offset IS the release
## altitude. So the units appear at the transport's cruising height and float down from
## there, using the garrison's ordinary spread-onto-free-ground placement rather than a
## second copy of it.
func _release_cargo(a_actor: Commandable) -> void:
	var hold: Garrison = a_actor.get_node_or_null("Garrison") as Garrison
	if hold == null:
		return
	var altitude: float = a_actor.height_offset()
	for unit: Commandable in hold.occupants():
		if unit.movement == null:
			continue
		var canopy: Node3D = _attach_canopy(unit)
		unit.movement.begin_parachute_descent(altitude, _cut_canopy.bind(canopy))
	hold.evacuate(message.map)


## Where the transport is aimed once it is empty: on along the heading it arrived on, far
## enough to be clear of the map whichever way that points (see OffMapArrival.exit_xz).
##
## The heading comes from the aircraft's own facing rather than from the entry point,
## which this command was never told. They are the same line — the transport has flown
## straight down it — and the facing is the one the player can see.
func _resolve_egress_point(a_actor: Commandable) -> Vector3:
	var heading: Vector2 = (
		VU.inXZ(a_actor.movement.get_facing()) if a_actor.movement != null else Vector2.ZERO
	)
	var exit_xz: Vector2 = OffMapArrival.exit_xz(message.map, a_actor.xz_position, heading)
	return Vector3(exit_xz.x, a_actor.global_position.y, exit_xz.y)


## Hang a canopy over [a_unit], and return it so the descent's touchdown callback can take it
## away again.
##
## THE CANOPY BELONGS TO THE DESCENT, NOT TO THIS COMMAND — a drop near the map edge sends the
## transport off the board before a canopy reaches the ground, so a run that tidied up after
## itself would cut parachutes out from under units still in the air. Parented to the unit
## rather than to its MeshVisual, so it plays no part in the tint, the shading or
## `model_top_offset()`. Why:
## gdd/systems/macroeconomics/sanctions/off-map-abilities.md §The canopy is a prop.
func _attach_canopy(a_unit: Commandable) -> Node3D:
	var canopy: Node3D = CANOPY_SCENE.instantiate() as Node3D
	if canopy == null:
		return null
	a_unit.add_child(canopy)
	var visual: MeshVisual = a_unit.get_node_or_null("MeshVisual") as MeshVisual
	canopy.position = Vector3(0.0, visual.model_top_offset() if visual != null else 0.0, 0.0)
	return canopy


## Touchdown: the canopy has done its job. Guarded on validity because the unit may have
## died on the way down, taking the canopy with it before this could run.
func _cut_canopy(a_canopy: Node3D) -> void:
	if a_canopy != null and is_instance_valid(a_canopy):
		a_canopy.queue_free()


#endregion


#region Debug
func _to_string() -> String:
	return "AirDropRun(%s)" % ("approach" if _phase == Phase.APPROACH else "egress")
#endregion
