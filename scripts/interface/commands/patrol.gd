class_name Patrol
extends Command

## Endlessly-cycling patrol between two or more waypoints with aggro checking
## along the way (identical to AttackMove's aggro behaviour). On reaching the
## last waypoint the unit reverses through the route back to the first, then
## reverses again, bouncing indefinitely.
##
## State model — two arrays plus `message.position` (the current destination):
##   _before  waypoints visited in the current sweep, earliest first
##   _after   waypoints still to visit in the current sweep
##
## When the first Patrol is issued to a unit that has no existing patrol command,
## the unit's current position is prepended to _before via for_actor(), giving the
## route an anchor to return to. Subsequent Shift+Patrol clicks are queued
## normally; on arrival the active Patrol absorbs leading Patrol entries from the
## CommandReceiver queue into _after before deciding what to do next.

var _before: Array[Vector3] = []
var _after: Array[Vector3] = []
## Guards against fulfilling the command before navigation has even started.
## Set true the first time should_move() runs, which always precedes can_act()
## returning true (they're in elif branches).
var _nav_loaded: bool = false


func _init(a_message: CommandMessage, p_before: Array[Vector3] = [], p_after: Array[Vector3] = []) -> void:
	super(a_message)
	_before = p_before.duplicate()
	_after = p_after.duplicate()


## Use this factory when issuing Patrol in response to player input. If the actor
## has no existing Patrol command anywhere in its chain, the actor's current
## position is added to _before so the unit has a return anchor; otherwise the
## new waypoint is simply appended to the ongoing route.
static func for_actor(a_actor: Commandable, a_message: CommandMessage) -> Patrol:
	if a_actor.command_receiver.has_patrol_command():
		return Patrol.new(a_message)
	return Patrol.new(a_message, [a_actor.global_position])


#region State updates
func get_updated_state(a_actor: Commandable) -> Command:
	var aggro: Command = a_actor.get_aggro_near_position()
	return aggro if aggro != null else self


func should_move(_a_actor: Commandable) -> bool:
	_nav_loaded = true
	return true


func can_act(a_actor: Commandable) -> bool:
	return _nav_loaded \
			and a_actor.movement != null \
			and a_actor.movement.is_navigation_finished()


func fulfill_action(a_actor: Commandable) -> Variant:
	# Absorb any Patrol commands the player queued up while this leg was running.
	var extra: Array[Vector3] = a_actor.command_receiver.consume_leading_patrol_positions()
	_after.append_array(extra)

	if not _after.is_empty():
		# More waypoints ahead — advance in the current direction.
		_before.append(message.position)
		var next: Vector3 = _after.pop_front()
		var new_msg: CommandMessage = CommandMessage.new(message.map, null, null, next)
		return Patrol.new(new_msg, _before.duplicate(), _after.duplicate())
	else:
		# End of the current sweep — reverse and head back the way we came.
		# _before holds [origin … prev], so reversed gives the return path.
		var new_after: Array[Vector3] = _before.duplicate()
		new_after.reverse()
		if new_after.is_empty():
			return null  # degenerate: only one waypoint, nothing to return to
		var next: Vector3 = new_after.pop_front()
		var new_msg: CommandMessage = CommandMessage.new(message.map, null, null, next)
		return Patrol.new(new_msg, [message.position], new_after)
#endregion


#region Debug
func _to_string() -> String:
	return "Patrol: %s (behind=%d ahead=%d)" % [message.position, _before.size(), _after.size()]
#endregion
