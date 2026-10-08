class_name Locomotion
extends Node

## How a piece moves, behind ONE interface whatever the strategy. Whatever drives the piece
## sets a GOAL — a place, how to arrive there, and optionally the piece being pursued — and
## locomotion decides what that means this tick: path toward it, ignore it, or keep flying
## because this mover cannot stop. The driver never learns which.
##
## Strategies are subclasses. `Movement` is the NAVIGATED one (navmesh path, RVO avoidance,
## the ground, hover and flight modes). The design, and the strategies still to come:
## gdd/systems/authoring/composition-rework.md §Locomotion is bigger than `Movement`.

#region Goal
## How to arrive at the goal. STOP brakes and settles there; PASS_THROUGH keeps speed, for a
## waypoint with more to follow or a run that goes on past its target.
enum Arrival { STOP, PASS_THROUGH }

## What `tick` did with the goal this tick.
enum Progress {
	MOVING,  ## still on its way
	ARRIVED,  ## reached the goal
	HOLDING,  ## chose not to move — already against the piece it is pursuing
}

## The place to steer at. For a pursued piece this is where it is now, or a point beside it
## the driver chose (a structure's approach cell).
var goal_position: Vector3 = Vector3.ZERO
var goal_arrival: Arrival = Arrival.STOP
## The piece being pursued, or null for a plain place. Untyped: it may hold a freed piece.
var _goal_entity: Variant = null


## Set the goal for this tick. Calling it every tick with an unchanged goal is expected and
## costs nothing; a strategy acts only on what changed.
func set_goal(
	a_position: Vector3, a_arrival: Arrival = Arrival.STOP, a_entity: Entity = null
) -> void:
	goal_position = a_position
	goal_arrival = a_arrival
	_goal_entity = a_entity


## The pursued piece, or null when the goal is a plain place or the piece has left the field —
## freed, or garrisoned (off the tree, with no position, until it is released).
func goal_entity() -> Entity:
	var entity: Variant = _goal_entity
	if entity == null or not is_instance_valid(entity):
		return null
	return entity as Entity if (entity as Entity).is_inside_tree() else null


#endregion


#region Strategy — overridden
## Whether this piece can move at all. An immobile strategy accepts goals and ignores them.
func can_move() -> bool:
	return false


## Act on the goal for one tick.
func tick() -> Progress:
	return Progress.ARRIVED


## The goal is reached: settle there the way this strategy settles.
func arrive() -> void:
	pass


## Stop dead, now. A mover that cannot stop does what it can.
func stop() -> void:
	pass


## Whether this mover can come to rest where it is. One that cannot keeps moving when its
## driver has nothing more for it — settle() decides how.
func can_hold_still() -> bool:
	return true


## Nothing left to go to. A mover that can stop stops; one that cannot loops around
## `a_anchor` — the last place its goal was — or around wherever it already circles when null.
func settle(_a_anchor: Variant = null) -> void:
	stop()
#endregion
