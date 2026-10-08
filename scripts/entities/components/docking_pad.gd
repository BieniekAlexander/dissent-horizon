@tool
class_name DockingPad
extends Marker3D

## One parking space on a DockingBay. Authored as a Marker3D child of the bay, positioned
## where an aircraft should come to rest — so capacity is not a number anyone types, it is
## how many pads the airfield's artist put on the deck. A bay's capacity and the visible
## parking spaces can therefore never disagree.
##
## A Marker3D rather than a bare Node3D so the space is visible in the editor viewport
## while the airfield is being laid out; it draws nothing at runtime.

#region Properties
## Height above the terrain at which a docked unit rests here, in world units. Zero puts
## it on the ground; raise it for a pad sitting on a raised deck. Read by Rearm as the
## descent's target height offset, so the aircraft settles onto the deck rather than
## sinking through it to ground level.
@export var deck_height: float = 0.0

## The unit that has claimed this pad — either parked on it or inbound to it. One field
## covers both because a reservation and an occupancy exclude exactly the same things: no
## second aircraft may target a pad another is already flying toward.
##
## Never read directly; ask through is_free() / claimed_by(), which also treat a freed
## unit as gone. A pad's claimant can be destroyed mid-approach, and a freed reference
## reads as null in Godot only for `== null`, not for a typed field's other uses.
var _claimant: Actor = null
#endregion


#region Public API
## True when nothing has claimed this pad. A claimant that has since been freed does not
## hold the pad — an aircraft shot down on final approach must not strand its space.
func is_free() -> bool:
	return not is_instance_valid(_claimant)


## The live unit holding this pad, or null. Collapses the freed-claimant case so callers
## never have to repeat the validity check.
func claimed_by() -> Actor:
	return _claimant if is_instance_valid(_claimant) else null


## Claim this pad for `unit`. Returns false, changing nothing, when someone else holds it
## — the caller (DockingBay.reserve) is expected to have picked a free pad, so a refusal
## here means two claims raced within one tick.
func claim(a_unit: Actor) -> bool:
	if not is_free() and claimed_by() != a_unit:
		return false
	_claimant = a_unit
	return true


## Drop `unit`'s claim. A no-op when someone else holds the pad, so a stale release — from
## a Rearm command being torn down after its aircraft already left and another arrived —
## cannot evict the current occupant.
func release(a_unit: Actor) -> void:
	if claimed_by() == a_unit or not is_instance_valid(_claimant):
		_claimant = null


## Where an aircraft parked here sits, in world space. XZ is the marker's own position;
## Y is left to the caller, which resolves it from the terrain plus deck_height (aerial
## units have their world Y driven per-tick by Actor, so a fixed Y here would be
## overwritten immediately).
func dock_position() -> Vector3:
	return global_position
#endregion
