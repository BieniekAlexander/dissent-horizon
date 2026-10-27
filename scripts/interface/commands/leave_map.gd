class_name LeaveMap
extends MoveCommand

## Fly to a point beyond the map's edge and leave the game there: a transport that has done
## its work going home. The piece removes itself once it is clear of the play area by
## OffMapArrival.EXTERIOR_MARGIN — the same remove a called-in piece enters at — so the point
## must lie at least that far out, or the piece arrives and hovers there.
##
## NOT A PLAYER-FACING COMMAND, like AirDropRun: issued by a scenario chain (EventCommandPoint
## `leave_map`) after a transport has unloaded. Added for prologue mission 1's allied relief
## (Alex, 2026-10-21). The destination is NOT snapped to the navmesh, which would pull it back
## onto the map; only something that flies can reach it.


## Arriving at the point is not the end; leaving the map is.
func ends_on_arrival() -> bool:
	return false


func can_act(a_actor: Actor) -> bool:
	return OffMapArrival.has_left(message.map, a_actor.xz_position)


func fulfill_action(a_actor: Actor) -> Variant:
	a_actor.queue_free()
	return null


func _to_string() -> String:
	return "LeaveMap"
