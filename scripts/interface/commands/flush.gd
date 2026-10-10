class_name Flush
extends Occupy

## A Flusher's order onto a flushable garrison its ENEMY holds: walk up as Occupy does, then kill
## everything inside (Garrison.flush) and enter in the same tick. The flush makes the room, so
## capacity is asked of the emptied host, never of the full one.
## Rules: gdd/systems/combat/garrison-and-transport.md §Flushing a garrison.


#region Preconditions
## Valid when the actor storms garrisons, and the target is a built, flushable garrison held by
## the actor's enemy whose masks would admit the actor. Not a garrison the actor could simply
## enter — that is Occupy's, and a flush there would kill friends.
static func meets_precondition(actor: Actor, message: CommandMessage) -> PreconditionFailureCause:
	if not Flusher.flushes(actor) or not (message.target is Actor):
		return PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
	var host := message.target as Actor
	return (
		PreconditionFailureCause.NONE
		if is_instance_valid(host) and actor.is_enemy_of(host) and _stormable(actor, host)
		else PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
	)


## Whether `a_actor` could storm `a_host`'s garrison, whoever holds it: built, flushable, and
## admitting the actor once emptied.
static func _stormable(a_actor: Actor, a_host: Actor) -> bool:
	var garrison := a_host.get_node_or_null("Garrison") as Garrison
	return (
		garrison != null
		and garrison.flushable
		and a_host.is_built
		and a_actor.can_move()
		and garrison.admits(a_actor)
		and garrison.capacity >= Garrison.size_of(a_actor)
	)


#endregion


#region State updates
## Adjacent, and the host will take the actor once it is dealt with: emptied if its enemy
## still holds it, or entered as it stands if the holders left on the way (Occupy's rule).
func can_act(a_actor: Actor) -> bool:
	if not is_instance_valid(message.target):
		return false
	if not SU.unit_is_close_to_target(a_actor, message.target):
		return false
	var host := message.target as Actor
	if a_actor.is_enemy_of(host):
		return _stormable(a_actor, host)
	return host.garrison != null and host.garrison.accepts(a_actor)


## Flush the host if its enemy still holds it, then enter — if the emptied host is one the
## actor may enter at all. A neutral building its occupants had adopted reverts to neutral when
## flushed, so it can be entered; a host the enemy OWNS stays the enemy's, and is only emptied.
func fulfill_action(a_actor: Actor) -> Variant:
	var host := message.target as Actor
	if host == null or host.garrison == null:
		return null
	if a_actor.is_enemy_of(host):
		host.garrison.flush(a_actor)
	if not Occupy.host_admits(a_actor, host):
		_clear_collision_exception()
		_clear_rvo_suppression()
		return null
	return super(a_actor)


#endregion


#region Debug
func _to_string() -> String:
	return "Flush: %s" % message.position
#endregion
