class_name CommandReceiver
extends RefCounted

enum Disposition {
	PASSIVE,
	AGGRESSIVE
}

var owner: Commandable
var _command: Command = null
var _command_queue: Array[Command] = []
var _disposition: Disposition = Disposition.PASSIVE

func initialize(a_owner: Commandable) -> void:
	owner = a_owner
	_command_queue = []

func has_pending_work() -> bool:
	return _command != null or not _command_queue.is_empty()

## True when the unit has no user-set command — either genuinely idle or only
## running the fallback placeholder. Queued commands count as non-idle.
func is_idle() -> bool:
	return _command_queue.is_empty() and (_command == null)

func receive_damage(attacker: Commandable, amount: float) -> void:
	owner.hp -= amount

	if owner.hp > 0 and _command == null and attacker != null and !(_disposition == Disposition.PASSIVE):
		update_commands(
			Command.new(CommandMessage.new(owner.map, attacker, null, attacker.global_position)),
			true,
			true
		)

func load_destination(command: Command) -> void:
	if owner.movement != null:
		owner.movement.set_target_position(command.message.position)

func _process_commands() -> void:
	var new_commands: Variant = _command.get_updated_state(owner) if _command != null else null

	if is_same(new_commands, null):
		_command = null
	elif !is_same(new_commands, _command) and !is_same(new_commands, null):
		update_commands(new_commands, true, true)
	elif _command.can_act(owner):
		new_commands = _command.fulfill_action(owner)

		if owner.movement != null:
			owner.movement.set_velocity(Vector3.ZERO)

		if is_same(new_commands, null):
			_command = null
		if new_commands != _command and !is_same(new_commands, null):
			_command = null
			update_commands(new_commands, true, true)
	elif owner.movement != null and _command.should_move(owner):
		if owner.movement.target_position != _command.message.position:
			load_destination(_command)
			#owner._stop_timer.start()

		if !owner.movement.is_navigation_finished():
			var next_path_position: Vector3 = owner.movement.get_next_path_position()
			# Keep velocity XZ-only so the RVO avoidance system receives a clean
			# 2D input.  Vertical terrain tracking is handled per-tick in
			# Commandable._physics_process via Map.terrain_height_at().
			var prelim_velocity = owner.global_position.direction_to(next_path_position) * owner.SPEED_PER_SECOND
			prelim_velocity.y = 0.0
			owner.movement.set_velocity(prelim_velocity)
		else:
			owner.movement.set_target_position(owner.global_position)
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
