class_name Wander
extends MoveCommand

## Never-completing "mill about a spot" command. Every [INTERVAL] seconds the actor
## picks a fresh navmesh point within [RADIUS] of the anchor it was issued at and
## walks there; on arrival it simply idles until the next pick. The command never
## returns null, so it stays on the unit for the rest of that unit's life unless
## something else replaces it.
##
## Used for the neutral Terrestrials a [Shelter] produces: each is issued a Wander
## anchored on its shelter's centre, so it loiters around the building. Because
## every destination is snapped onto the navmesh — from which a structure's
## footprint cells are excluded — a wanderer never tries to path through the
## shelter it belongs to.
##
## The anchor is the position the command was ISSUED at, captured once at _init;
## `message.world_position` is then reused as the current leg's destination, so
## the waypoint/command-line indicators keep pointing at where the unit is
## actually walking.

#region Constants
## World-units of slack around the anchor. Each destination is drawn uniformly
## from the disc of this radius, then snapped to the navmesh.
const RADIUS: float = 3.0

## Seconds between destination picks. Long enough that a wanderer spends most of its
## time standing still or ambling, rather than twitching to a new heading every second.
const INTERVAL: float = 10.0
#endregion

#region Properties
## The point to wander around — the command's issue position, held separately
## because message.world_position is rewritten with each new destination.
var _anchor: Vector3

## Seconds until the next destination pick. Starts at 0 so the first tick picks
## immediately rather than leaving the unit parked for a full interval.
var _cooldown: float = 0.0
#endregion


#region Preconditions
static func requires_position() -> bool:
	return true


## Only a unit that can actually navigate can wander.
static func meets_precondition(
	actor: Commandable, _message: CommandMessage
) -> PreconditionFailureCause:
	return (
		PreconditionFailureCause.NONE
		if actor != null and actor.can_move()
		else PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
	)


#endregion


#region Lifecycle
func _init(a_message: CommandMessage) -> void:
	super(a_message)
	_anchor = a_message.position


#endregion


#region State updates
## Tick the pick timer and retarget when it elapses. Always returns self — this
## command is deliberately unfinishable.
func get_updated_state(a_actor: Commandable) -> Variant:
	if not a_actor.can_move():
		return self
	_cooldown -= 1.0 / Engine.get_physics_ticks_per_second()
	if _cooldown <= 0.0:
		_cooldown = INTERVAL
		_retarget(a_actor)
	return self


## Draw a new destination on the navmesh within RADIUS of the anchor and steer
## the actor at it. The nav target is set here (rather than left to
## CommandReceiver's move branch) so that is_navigation_finished() flips to false
## on the same tick — otherwise a unit parked at its previous destination would
## keep answering can_act() and never set off.
func _retarget(a_actor: Commandable) -> void:
	var map: Map = message.map if message.map != null else a_actor.map
	# Uniform over the disc: sqrt() on the radial term, otherwise picks bunch up
	# near the anchor.
	var angle: float = SU.rng.randf() * TAU
	var distance: float = sqrt(SU.rng.randf()) * RADIUS
	var candidate: Vector3 = _anchor + Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)
	if map != null:
		# Sample the terrain height first: the navmesh is 3D, so snapping from a
		# point at the wrong altitude can resolve to a different cell entirely.
		candidate.y = map.terrain_height_at(VU.in_xz(candidate))
		candidate = map.nearest_navmesh_point(candidate)
	message.world_position = candidate
	a_actor.movement.set_target_position(candidate)


func should_move(_a_actor: Commandable) -> bool:
	return true


## "Arrived" — the actor has nothing to do until the next pick. Answering true
## here is what keeps the command alive: CommandReceiver drops a command whose
## navigation finished in the move branch, so a wanderer must be caught by
## can_act/fulfill_action instead.
func can_act(a_actor: Commandable) -> bool:
	return a_actor.movement == null or a_actor.movement.is_navigation_finished()


## Idle in place; returning self keeps the command running forever.
func fulfill_action(_a_actor: Commandable) -> Variant:
	return self


#endregion


#region Debug
func _to_string() -> String:
	return "Wander: %s (anchor %s)" % [message.position, _anchor]
#endregion
