class_name Defend
extends MoveCommand


## This order exists in order to shoot, so an empty charged loadout makes it undoable for
## now. The receiver stands it down into the queue rather than have the unit fly at
## something it cannot touch — it resumes once the unit has been back to an airfield.
func requires_ammo() -> bool:
	return true


## An order to fight in an area is an order to shoot, so it lifts hold fire as an attack does.
func releases_hold_fire() -> bool:
	return true


## A Defend order considers EVERY enemy structure, unarmed ones included, on top of what
## other orders pick up (which stop at NON_COMBAT_UNITS). Set here rather than by whoever
## builds the message, because four places build Defend messages and a floor set at each
## would drift; widening the message itself means any copy of it carries the same floor.
## Ranking is unchanged — an unarmed structure is taken only when nothing more urgent is in
## the region. Why: gdd/systems/combat/target-acquisition.md §A Defend order also considers
## every enemy structure.
const TARGET_PRIORITY_FLOOR: Entity.TargetPriority = Entity.TargetPriority.NON_COMBAT_STRUCTURES


func _init(a_message: CommandMessage) -> void:
	super(a_message)
	message.target_priority = TARGET_PRIORITY_FLOOR


#region State updates
## Set once the unit first reaches its post, and cleared only if the post itself moves.
##
## A LATCH, not a live distance test, and the difference matters entirely for aircraft. An
## aeroplane cannot stand on its post — it circles it — so a live "am I within arrival
## distance" test flickers: the orbit carries it out, should_move goes true, the receiver
## drives it back at CRUISE speed, it arrives, the orbit pushes it out again. The unit ends
## up scything around its post at full speed instead of loitering over it. Latched, the
## orbit owns the unit from the moment it arrives and holds it at orbit_speed, which is the
## same circuit an idle aircraft flies.
var _on_station: bool = false


func can_act(a_actor: Actor) -> bool:
	# "Arrived at post": hold here and keep guarding. Reuses the nav agent's own arrival
	# test — the same one a plain MoveCommand uses — instead of a hand-rolled distance
	# threshold. The target_position guard stops a stale destination from the previous leg
	# reading as "finished" before this unit has actually been pointed at its post.
	if a_actor.movement == null:
		return true
	if not a_actor.movement.target_position.is_equal_approx(message.position):
		_on_station = false
		return false
	if a_actor.movement.is_navigation_finished():
		_on_station = true
	return _on_station


func should_move(a_actor: Actor) -> bool:
	# Travel to post exactly like a plain move: drive until the nav agent reports arrival.
	# While the post isn't yet loaded as the destination, keep moving so the receiver loads
	# it (CommandReceiver._process_commands) rather than stalling short of it.
	if a_actor.movement == null:
		return false
	if not a_actor.movement.target_position.is_equal_approx(message.position):
		return true
	return not _on_station


func get_updated_state(a_actor: Actor) -> Variant:
	# Scan for threats around the DEFENDED REGION — the shared aggro_shape at its own world
	# position — not this unit's post, so every defender reacts to the same incursion and a
	# bait can't peel one unit off alone. Passing the shape node as the centre makes
	# get_aggro_near_position read its global_position; each unit then still chases the
	# target nearest to itself (it sorts by proximity). With no region shape assigned, fall
	# back to the target/post as before.
	var a_center: Variant
	if message.aggro_shape != null:
		a_center = message.aggro_shape
	elif message.target != null:
		a_center = message.target
	else:
		a_center = message.position
	var new_command: MoveCommand = a_actor.get_aggro_near_position(
		a_center, message.aggro_shape, message.target_priority
	)
	if new_command != null:
		_leash_to_defended_area(a_actor, new_command)
	return new_command if new_command != null else self


## Hand the engagement the SAME region it was acquired in, so acquiring and releasing a target
## are one test rather than two. With no region shape authored, the defended area is the
## defender's own aggro range centred on the post — exactly the area the scan just used.
## Why, and the per-tick flicker the two disagreeing produced:
## gdd/systems/combat/target-acquisition.md §The leash must be the region.
func _leash_to_defended_area(a_actor: Actor, a_command: MoveCommand) -> void:
	if message.aggro_shape != null:
		a_command.message.aggro_shape = message.aggro_shape
		a_command.message.aggro_center = message.aggro_shape.global_transform.origin
		return
	a_command.message.aggro_shape = a_actor.aggro_shape_for(a_command.message.target)
	a_command.message.aggro_center = _post_position()


## The world point this order defends: its target's position while it has one (a defended
## unit moves), otherwise the post it was given.
func _post_position() -> Vector3:
	if message.target != null and is_instance_valid(message.target):
		return message.target.global_position
	return message.position


func fulfill_action(_a_actor: Actor) -> Variant:
	return self
#endregion
