class_name CommandReceiver
extends RefCounted

#region Constants
enum Disposition {
	PASSIVE,
	AGGRESSIVE
}
#endregion

#region Properties
var owner: Commandable
var _command: Command = null
var _command_queue: Array[Command] = []
var _disposition: Disposition = Disposition.PASSIVE

## The unit currently being followed and the command driving that follow, both
## captured while the target is still valid. Needed because a freed reference
## reads as null in Godot (== null is true), so once the followed unit dies its
## death is indistinguishable from a plain terrain move unless we remembered it.
var _followed: Commandable = null
var _follow_cmd: Command = null
#endregion

#region Public API
func initialize(a_owner: Commandable) -> void:
	owner = a_owner
	_command_queue = []

func has_pending_work() -> bool:
	return _command != null or not _command_queue.is_empty()

## Returns the active command followed by any queued commands, in execution order.
func get_command_chain() -> Array[Command]:
	var chain: Array[Command] = []
	if _command != null:
		chain.append(_command)
	chain.append_array(_command_queue)
	return chain

## True when the unit has no user-set command — either genuinely idle or only
## running the fallback placeholder. Queued commands count as non-idle.
func is_idle() -> bool:
	return _command_queue.is_empty() and (_command == null)

func has_patrol_command() -> bool:
	if _command is Patrol:
		return true
	for cmd: Command in _command_queue:
		if cmd is Patrol:
			return true
	return false

## Pops and returns the positions of every leading Patrol command from the front
## of the queue (stopping at the first non-Patrol entry). Used by Patrol.fulfill_action
## to absorb Shift+Patrol waypoints at arrival time.
func consume_leading_patrol_positions() -> Array[Vector3]:
	var positions: Array[Vector3] = []
	while not _command_queue.is_empty():
		var front: Command = _command_queue.front()
		if front is Patrol:
			positions.append((front as Patrol).message.position)
			_command_queue.pop_front()
		else:
			break
	return positions

func load_destination(command: Command) -> void:
	if owner.movement != null:
		owner.movement.set_target_position(command.message.position)

func update_commands(a_commands: Variant, add_to_queue: bool = false, prepend: bool = false) -> void:
	if a_commands == null:
		_command_queue = []
		_command = null
	elif a_commands is Command:
		if add_to_queue and prepend:
			if _command != null:
				_command_queue.push_front(_command)
			_command = a_commands
		elif add_to_queue and !prepend:
			_command_queue.append(a_commands)
		else:
			_command_queue = []
			_command = a_commands
	elif a_commands is Array and a_commands.size() > 0:
		if add_to_queue and prepend:
			if _command != null:
				_command_queue.assign(a_commands.slice(1) + [_command] + _command_queue)
			else:
				_command_queue.assign(a_commands.slice(1) + _command_queue)
			_command = a_commands[0]
		elif add_to_queue and !prepend:
			_command_queue.append_array(a_commands)
		else:
			_command = a_commands[0]
			_command_queue = a_commands.slice(1)
	else:
		push_error("Command argument is unsupported, arg=%s" % a_commands)
#endregion

#region Command processing
func _process_commands() -> void:
	var new_commands: Variant = _command.get_updated_state(owner) if _command != null else null

	if is_same(new_commands, null):
		# Command dropped (e.g. target died, left aggro range, or command fulfilled).
		# For FLYING units, anchor to the command's last-known destination so the
		# orbit starts around where the action ended.
		if _command != null and owner.movement != null \
				and owner.movement.mode == Movement.Mode.FLYING:
			owner.movement.set_anchor(_command.message.position)
		_command = null
		if owner.movement != null:
			owner.movement.is_final_leg = false
			if owner.movement.mode == Movement.Mode.FLYING:
				# Keep the unit moving along its orbit while idle.
				owner.movement.set_velocity(owner.movement.compute_orbit_velocity())
			else:
				# TODO(RVO experiment): feed idle units a zero velocity so they keep
				# refreshing their entry in the avoidance simulation. Without this, a unit
				# that finishes moving and goes idle stops calling set_velocity entirely,
				# so its last non-zero velocity can linger in the RVO sim — making nearby
				# movers steer around a "ghost" heading instead of treating it as the
				# stationary obstacle it now is. Zeroing here marks it as parked.
				# CAVEAT: this also lets RVO compute a (possibly non-zero) avoidance
				# velocity for the idle unit, which _on_velocity_computed will apply — so
				# idle units may now drift aside when a mover pushes into them. That is in
				# tension with "enemies don't get out of the way"; if it looks wrong, the
				# fix is to keep feeding 0 here but suppress *applying* avoidance velocity
				# for commandless units in Commandable._on_velocity_computed.
				owner.movement.set_velocity(Vector3.ZERO)
	elif !is_same(new_commands, _command) and !is_same(new_commands, null):
		update_commands(new_commands, true, true)
	elif _command.can_act(owner):
		new_commands = _command.fulfill_action(owner)

		if owner.movement != null:
			owner.movement.is_final_leg = false
			owner.movement.set_velocity(Vector3.ZERO)

		if is_same(new_commands, null):
			_command = null
		if new_commands != _command and !is_same(new_commands, null):
			_command = null
			update_commands(new_commands, true, true)
	elif owner.movement != null and _command.should_move(owner):
		var followed: Commandable = _follow_target()
		if followed != null:
			# Remember the live relationship so we can spot the target's death next
			# tick (a freed reference reads as null, so we can't detect it after).
			_followed = followed
			_follow_cmd = _command
		else:
			# Not following (or no longer): if this same follow command's target has
			# died, end it rather than driving toward the origin (message.position
			# falls back to world_position == 0 once the target is gone).
			# _follow_cmd (a RefCounted we hold) is the reliable "we were following"
			# flag — _followed reads as null once freed, so it can't gate this.
			var target_died: bool = _follow_cmd != null and is_same(_follow_cmd, _command) \
					and not is_instance_valid(_followed)
			_followed = null
			_follow_cmd = null
			if target_died:
				if owner.movement.mode == Movement.Mode.FLYING:
					# message.position holds the last-updated target position from
					# before the target was freed — use it as the orbit anchor.
					owner.movement.set_anchor(_command.message.position)
					owner.movement.is_final_leg = false
					_command = null
					owner.movement.set_velocity(owner.movement.compute_orbit_velocity())
				else:
					owner.movement.set_velocity(Vector3.ZERO)
					owner.movement.is_final_leg = false
					_command = null
				return

		# Following: hold position once our MOVEMENT_OBSTRUCTION body would touch
		# the target's, but KEEP the command so we resume if the target moves off.
		if followed != null and _bodies_would_touch(followed):
			owner.movement.set_velocity(Vector3.ZERO)
			owner.movement.is_final_leg = false
			return

		if owner.movement.target_position != _command.message.position:
			load_destination(_command)

		if !owner.movement.is_navigation_finished():
			var next_path_position: Vector3 = owner.movement.get_next_path_position()
			# Keep velocity XZ-only so the RVO avoidance system receives a clean
			# 2D input.  Vertical terrain tracking is handled per-tick in
			# Commandable._physics_process via Map.terrain_height_at().
			var prelim_velocity: Vector3 = owner.global_position.direction_to(next_path_position) * owner.movement.speed_per_second
			prelim_velocity.y = 0.0
			# Brake only on the final queued destination, only for non-attack commands,
			# and only for non-FLYING units. Flying units approach at full speed and
			# decelerate naturally to orbit_speed once they transition to orbiting.
			owner.movement.is_final_leg = _command_queue.is_empty() \
					and not (_command is Attack) \
					and not (_command is Patrol) \
					and owner.movement.mode != Movement.Mode.FLYING
			owner.movement.set_velocity(prelim_velocity)
		else:
			# HOVERING/FLYING pass-through: when there are more waypoints after this
			# one, immediately load the next destination on the same tick rather than
			# nulling the command and restarting on the next tick. This eliminates the
			# one-tick standstill that would otherwise break the banking curve.
			if (owner.movement.mode == Movement.Mode.HOVERING \
					or owner.movement.mode == Movement.Mode.FLYING) \
					and not _command_queue.is_empty() and followed == null:
				_command = _command_queue.pop_front()
				load_destination(_command)
				owner.movement.is_final_leg = _command_queue.is_empty() \
						and not (_command is Attack) \
						and owner.movement.mode != Movement.Mode.FLYING
				var next_pos: Vector3 = owner.movement.get_next_path_position()
				var pv: Vector3 = owner.global_position.direction_to(next_pos) * owner.movement.speed_per_second
				pv.y = 0.0
				owner.movement.set_velocity(pv)
			else:
				owner.movement.is_final_leg = false
				if owner.movement.mode == Movement.Mode.FLYING and followed == null:
					# Arrived at destination with no further commands — orbit here.
					owner.movement.set_anchor(owner.global_position)
					_command = null
					owner.movement.set_velocity(owner.movement.compute_orbit_velocity())
				else:
					owner.movement.set_target_position(owner.global_position)
					# A follow keeps its command on arrival; a plain move ends.
					if followed == null:
						_command = null

func _update_state() -> void:
	if _command == null and not _command_queue.is_empty():
		_command = _command_queue.pop_front()

	# Delegate to the owner's command processor (Commandable._process_commands),
	# which routes structure-flavored commands (Train → Production.enqueue,
	# base Command → Production.set_rally) before falling back to this
	# receiver's default handling via _process_commands(). Calling our own
	# _process_commands() here would bypass that routing entirely, which is why
	# structure training and rally points silently did nothing.
	owner._process_commands()

	_reconcile_follow_avoidance()
#endregion

#region Private helpers
## The friendly unit this unit is currently "following" — i.e. its active command
## moves it toward another unit on its own team — or null. Used both to suppress
## reciprocal avoidance and to stop at the followed unit's body.
func _follow_target() -> Commandable:
	if _command == null or not _command.should_move(owner):
		return null
	var t: Entity = _command.message.target
	if t != null and is_instance_valid(t) and t is Commandable \
			and t != owner and t.is_in_group("unit") \
			and (t as Commandable).commander_id == owner.commander_id:
		return t as Commandable
	return null

## True when this unit's MOVEMENT_OBSTRUCTION body would overlap `other`'s — i.e.
## their centre-to-centre XZ distance is within the sum of their body radii.
func _bodies_would_touch(other: Commandable) -> bool:
	var gap: float = VU.inXZ(owner.global_position).distance_to(VU.inXZ(other.global_position))
	var reach: float = owner.bounding_radius(CollisionLayers.Mask.MOVEMENT_OBSTRUCTION) \
			+ other.bounding_radius(CollisionLayers.Mask.MOVEMENT_OBSTRUCTION)
	return gap <= reach

## Suppress reciprocal RVO avoidance between this unit and the one it follows so
## the follower can close in without the pair shoving each other apart. Recomputed
## every tick, so it clears when the command changes, the target dies, or idle.
func _reconcile_follow_avoidance() -> void:
	if owner.movement == null:
		return
	owner.movement.set_avoidance_follow_target(_follow_target())
#endregion
