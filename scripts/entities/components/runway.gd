@tool
class_name Runway
extends Marker3D

## One runway on an airfield: a LINE that aircraft roll along, with a takeoff point at one
## end of it. Authored as a child of a DockingBay; an airfield may carry several.
##
## The marker's OWN POSITION is the takeoff point — the threshold an aircraft climbs out
## from and touches down on — and the line runs from there along the marker's forward axis
## for `length`. So placing one is "drop a marker at the end of the strip and point it down
## the tarmac", which is the same gesture as placing a DockingPad and reads correctly in the
## editor gizmo.
##
## DIRECTION MATTERS, and it is the reason the takeoff point is the marker rather than the
## middle. Both halves of the choreography are stated relative to it:
##   * DEPARTING — taxi from the pad onto the line, roll ALONG it toward the takeoff point,
##     climb out from there.
##   * ARRIVING  — descend along the extended centreline BEYOND the takeoff point, touch
##     down on it heading INTO the runway, roll off toward the pad.
## An aircraft therefore always meets the runway pointing the way a real one would, rather
## than dropping onto it sideways or backing in.

#region Configuration
## How far the strip runs from the takeoff point, in world units, along `heading()`.
@export var length: float = 6.0
#endregion

#region Occupancy
## The unit currently using this strip, or null. ONE AT A TIME — an aircraft rolling down a
## runway has the whole runway, and a second one taxiing onto it would drive through it.
##
## Deliberately a claim rather than collision: the taxi is a scripted drive along an
## authored line, so asking the physics engine about it would be answering a question the
## line already settles. It also scales the way the airfield does — more strips means more
## aircraft moving at once, which is what a second runway is FOR.
var _claimant: Commandable = null


## Free when nobody holds it, or when whoever did has been destroyed — a claim cannot
## outlive its claimant and strand the strip for the rest of the match.
func is_free() -> bool:
	return _claimant == null or not is_instance_valid(_claimant)


func claimed_by() -> Commandable:
	return _claimant if is_instance_valid(_claimant) else null


## Take the strip for `unit`. False when somebody else has it, which is the caller's cue to
## wait where it is and try again — a departing aircraft holds its pad, an arriving one
## keeps circling.
func claim(a_unit: Commandable) -> bool:
	if not is_free() and claimed_by() != a_unit:
		return false
	_claimant = a_unit
	return true


## Give the strip back. A no-op when somebody else holds it, so a stale release from a
## torn-down order cannot evict the aircraft currently rolling down it.
func release(a_unit: Commandable) -> void:
	if claimed_by() == a_unit or not is_instance_valid(_claimant):
		_claimant = null


#endregion


#region Public API
## The threshold: where a departure starts climbing and an arrival touches down.
func takeoff_point() -> Vector3:
	return global_position


## Unit vector pointing from the takeoff point INTO the runway (toward the apron end).
## +Z is this project's visual forward for a Node3D, the same convention Movement.get_facing
## uses, so a marker rotated to look down the strip yields the strip's direction.
func heading() -> Vector3:
	var forward: Vector3 = global_transform.basis.z
	forward.y = 0.0
	return forward.normalized() if not forward.is_zero_approx() else Vector3.FORWARD


## The far end of the strip — the end nearest the aprons.
func inner_point() -> Vector3:
	return takeoff_point() + heading() * length


## The point ON THE STRIP closest to `world_position`, clamped to the segment. Where an
## aircraft joins the runway from its pad, and where it leaves it again on the way back.
func nearest_point(a_world_position: Vector3) -> Vector3:
	var start: Vector2 = VU.inXZ(takeoff_point())
	var along: Vector2 = VU.inXZ(heading())
	var offset: Vector2 = VU.inXZ(a_world_position) - start
	var t: float = clampf(offset.dot(along), 0.0, length)
	var point: Vector2 = start + along * t
	return Vector3(point.x, takeoff_point().y, point.y)


## Where a landing aircraft lines up before it starts down: out beyond the takeoff point on
## the extended centreline, `run` short of it, so the descent is flown ALONG the strip.
## That is what makes an arrival read as an approach rather than a drop onto the numbers.
func approach_point(a_run: float) -> Vector3:
	return takeoff_point() - heading() * maxf(a_run, 0.0)


## How far this strip is from `world_position`, measured to the nearest point on it. Used to
## pick which runway a pad should use when an airfield has more than one.
func distance_to(a_world_position: Vector3) -> float:
	return VU.inXZ(a_world_position).distance_to(VU.inXZ(nearest_point(a_world_position)))
#endregion
