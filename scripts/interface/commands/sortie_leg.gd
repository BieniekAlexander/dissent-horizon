class_name SortieLeg
extends MoveCommand

## One transit leg of a called-in aircraft's sortie — in to its station, or home again — flown
## with nothing to do along the way. Its [Sortie] decides when the leg is over and replaces it;
## the leg itself never acts and never ends on arrival.
##
## NOT A PLAYER-FACING COMMAND, like AirDropRun: nothing offers it on the command grid, and it
## is the one order a sortie in transit admits.


## Always flying — a leg has no idle state.
func should_move(_a_actor: Actor) -> bool:
	return true


## Arriving is the Sortie's to judge, not the receiver's: without this, a fixed wing reaching
## the point would drop the order and start circling wherever it was.
func ends_on_arrival() -> bool:
	return false


func can_act(_a_actor: Actor) -> bool:
	return false


func _to_string() -> String:
	return "SortieLeg(%s)" % message.position
