class_name Defend
extends MoveCommand

#region State updates
func can_act(a_actor: Commandable) -> bool:
	# "Arrived at post": hold here and keep guarding. Reuses the nav agent's own arrival
	# test — the same one a plain MoveCommand uses — instead of a hand-rolled distance
	# threshold. The target_position guard stops a stale destination from the previous leg
	# reading as "finished" before this unit has actually been pointed at its post.
	if a_actor.movement == null:
		return true
	if not a_actor.movement.target_position.is_equal_approx(message.position):
		return false
	return a_actor.movement.is_navigation_finished()

func should_move(a_actor: Commandable) -> bool:
	# Travel to post exactly like a plain move: drive until the nav agent reports arrival.
	# While the post isn't yet loaded as the destination, keep moving so the receiver loads
	# it (CommandReceiver._process_commands) rather than stalling short of it.
	if a_actor.movement == null:
		return false
	if not a_actor.movement.target_position.is_equal_approx(message.position):
		return true
	return not a_actor.movement.is_navigation_finished()

func get_updated_state(a_actor: Commandable) -> Variant:
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
	var new_command: MoveCommand = a_actor.get_aggro_near_position(a_center, message.aggro_shape, message.target_priority)
	if new_command != null and message.aggro_shape != null:
		new_command.message.aggro_shape = message.aggro_shape
	return new_command if new_command != null else self

func fulfill_action(a_actor: Commandable) -> Variant:
	return self
#endregion
