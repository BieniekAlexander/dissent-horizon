class_name Occupy
extends MoveCommand


#region Preconditions
static func requires_position() -> bool:
	return true


## Valid when:
##   - the target is a Commandable that owns a Garrison component and is either
##     of the actor's own commander OR commanderless (neutral, id 0)
##   - that Garrison's occupancy masks admit the acting unit (frame, armour, and
##     locomotion style — see Garrison.admits). The masks replace what used to be a
##     hard-coded GROUNDED check here, so a hangar-style garrison can take
##     aircraft while a garrison with every mask cleared (a prison hold) takes no
##     voluntary occupants at all.
## Remaining capacity is deliberately NOT part of the precondition — it is checked in
## can_act(), so a unit ordered into a full garrison walks over and waits for a slot.
static func meets_precondition(
	actor: Commandable, message: CommandMessage
) -> PreconditionFailureCause:
	if not is_instance_valid(message.target) or not (message.target is Commandable):
		return PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
	return (
		PreconditionFailureCause.NONE
		if host_admits(actor, message.target as Commandable)
		else PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
	)


## Whether `a_occupant` may be ordered into `a_host`'s garrison — the whole of this
## command's rule, stated with no CommandMessage so the reverse order can ask it too.
##
## [Embark] is issued to the HOST and needs exactly this answer about the unit it is
## calling in. Asking through here rather than restating the masks is the same discipline
## _resolve_command_class follows when it delegates to this precondition: a second copy of
## "which units a garrison takes" is a copy that rots, and this one already did once.
##
## REMAINING CAPACITY IS DELIBERATELY NOT ASKED. A unit ordered into a full garrison walks
## over and waits for a slot, which is why it is checked in can_act instead. Embark adds
## the capacity test on its own, because the player hovering a unit wants to know whether
## calling it in would achieve anything.
static func host_admits(occupant: Commandable, host: Commandable) -> bool:
	if occupant == null or not is_instance_valid(occupant):
		return false
	if host == null or not is_instance_valid(host):
		return false
	# A garrison-capable unit cannot occupy itself.
	if host == occupant:
		return false
	var host_garrison := host.get_node_or_null("Garrison") as Garrison
	if host_garrison == null:
		return false
	if not host.is_built:
		return false
	if not occupant.can_move() or not host_garrison.admits(occupant):
		return false
	# Own-team garrisons and commanderless (neutral) garrisons are both occupiable;
	# an enemy-held garrison is not.
	return host.commander_id == occupant.commander_id or host.commander_id == 0


#endregion

#region Properties
## The actor that currently holds a MOVEMENT_OBSTRUCTION collision exception
## against the target, so we know whose exception to clear on teardown.
var _excluded_actor: Commandable = null

## The actor that registered garrison intent on the HOVERING host, so we can
## unregister if the command is replaced before the actor actually garrisons.
var _garrison_registered_actor: Commandable = null

## While approaching, the actor would physically collide with the target's
## MOVEMENT_OBSTRUCTION body — stopping it short of garrison range (and tripping
## the slide-collision command-cancel in Commandable._on_velocity_computed).
## Exclude the target's body so the actor can move right up to / into it.

## Suppress RVO broadcasting on both the actor and the target so neither agent
## steers around the other during the approach.
##   - Actor's layers zeroed: target's mask no longer sees the actor → target
##     stops steering away from the approaching unit (the visible bug).
##   - Target's layers zeroed: actor's mask no longer sees the target → actor
##     goes straight in rather than being deflected sideways.
## Only affects units (Movement != null); structures don't participate in RVO.
var _rvo_suppressed_actor: Commandable = null
#endregion


#region Private helpers
func _ensure_collision_exception(a_actor: Commandable) -> void:
	if _excluded_actor != null:
		return
	if (
		is_instance_valid(a_actor)
		and is_instance_valid(message.target)
		and message.target is CollisionObject3D
	):
		a_actor.add_collision_exception_with(message.target)
		_excluded_actor = a_actor


## Restore normal collision between the actor and the target. Safe to call
## multiple times and when either node is already gone.
func _clear_collision_exception() -> void:
	if (
		is_instance_valid(_excluded_actor)
		and is_instance_valid(message.target)
		and message.target is CollisionObject3D
	):
		_excluded_actor.remove_collision_exception_with(message.target)
	_excluded_actor = null


func _ensure_rvo_suppression(a_actor: Commandable) -> void:
	if _rvo_suppressed_actor != null:
		return
	if is_instance_valid(a_actor) and a_actor.movement != null:
		a_actor.movement.suppress_avoidance_layers()
		_rvo_suppressed_actor = a_actor
	if is_instance_valid(message.target):
		var target := message.target as Commandable
		if target != null and target.movement != null:
			target.movement.suppress_avoidance_layers()


func _clear_rvo_suppression() -> void:
	if is_instance_valid(_rvo_suppressed_actor) and _rvo_suppressed_actor.movement != null:
		_rvo_suppressed_actor.movement.restore_avoidance_layers()
	_rvo_suppressed_actor = null
	if is_instance_valid(message.target):
		var target := message.target as Commandable
		if target != null and target.movement != null:
			target.movement.restore_avoidance_layers()


#endregion


#region State updates
## Cancel if the target is destroyed while the unit is en route.
## For HOVERING hosts, registers garrison intent on the first valid tick so the
## host knows to descend and can take off again once all pending units are inside.
func get_updated_state(a_actor: Commandable) -> Variant:
	if not is_instance_valid(message.target):
		_clear_collision_exception()
		_clear_rvo_suppression()
		return null
	_ensure_collision_exception(a_actor)
	_ensure_rvo_suppression(a_actor)
	var host := message.target as Commandable
	if (
		host != null
		and host.aerial != null
		and host.aerial.mode == Movement.Mode.HOVERING
		and host.garrison != null
		and _garrison_registered_actor == null
	):
		host.garrison.register_garrison_intent(a_actor)
		_garrison_registered_actor = a_actor
	return self


## The host, for the whole life of the order. A passenger must not steer around the very
## thing it is climbing into, and the host driving to meet it must not shove it aside.
##
## Stated here rather than left to the follow rule, which only exempts a friendly unit while
## the follower is still MOVING: a passenger that has arrived and is waiting for a slot in a
## full hold is exactly when the host is nearest and the shoving worst, and a NEUTRAL host
## (a Shelter) is never a follow target at all.
func avoidance_exception(_a_actor: Commandable) -> Commandable:
	return message.target as Commandable if is_instance_valid(message.target) else null


## While the host is a HOVERING unit that has not yet grounded, keep approaching
## unconditionally so the actor tracks the host's moving XZ position.
## Once grounded, fall back to the normal proximity check.
func should_move(a_actor: Commandable) -> bool:
	if not is_instance_valid(message.target):
		return false
	var host := message.target as Commandable
	if (
		host != null
		and host.aerial != null
		and host.aerial.mode == Movement.Mode.HOVERING
		and not host.aerial.is_grounded_temp()
	):
		return true
	return not SU.unit_is_close_to_target(a_actor, message.target)


## Occupy once adjacent and the garrison still has room.
## For HOVERING hosts the host descends automatically (driven by
## Commandable._update_state); this just waits until GROUNDED_TEMP.
func can_act(a_actor: Commandable) -> bool:
	if not is_instance_valid(message.target):
		return false
	if not SU.unit_is_close_to_target(a_actor, message.target):
		return false
	var garrison := message.target.get_node_or_null("Garrison") as Garrison
	# accepts() re-checks the masks alongside the room left, since the actor's own state
	# (its Movement mode, say) can change between the order and its arrival.
	if garrison == null or not garrison.accepts(a_actor):
		return false
	var host := message.target as Commandable
	if (
		host != null
		and host.aerial != null
		and host.aerial.mode == Movement.Mode.HOVERING
		and not host.aerial.is_grounded_temp()
	):
		return false
	return true


## Remove the acting unit from the scene tree into the garrison.
func fulfill_action(a_actor: Commandable) -> Variant:
	# Clear both exceptions before garrisoning — once garrisoned the actor leaves
	# the tree, so do the bookkeeping while its body is still resolvable.
	_clear_collision_exception()
	_clear_rvo_suppression()
	var garrison := message.target.get_node_or_null("Garrison") as Garrison
	if garrison == null:
		return null
	var host := message.target as Commandable
	if host != null and host.aerial != null and host.aerial.mode == Movement.Mode.HOVERING:
		# Only accept units that are still registered; units that died during
		# the descent removed themselves from the list via tree_exiting.
		if not a_actor in garrison._pending_garrison_units:
			return null
		garrison.unregister_garrison_intent(a_actor)
		_garrison_registered_actor = null
	garrison.garrison(a_actor)
	return null


#endregion


#region Lifecycle
## Replaced mid-approach (the player issued a new order), the command leaves without completing,
## so it drops both exceptions and the garrison intent here, while the actor is alive.
func on_released(_a_actor: Commandable) -> void:
	_clear_collision_exception()
	_clear_rvo_suppression()
	if is_instance_valid(_garrison_registered_actor) and is_instance_valid(message.target):
		var target := message.target as Commandable
		if target != null and target.garrison != null:
			target.garrison.unregister_garrison_intent(_garrison_registered_actor)
	_garrison_registered_actor = null


## The HOST's half only: a command freed with its actor (the actor died, or was consumed by a
## Compound sentence, mid-approach) never gets on_released, and the host would stay out of
## avoidance. It must not reach into the actor, which may be mid-teardown here — this used to
## restore the actor's avoidance too, and crashed reading its Movement (MoveCommand._notification).
## A destroyed actor takes its own exceptions with it, and leaves the host's pending list
## through its own tree_exiting hook (Garrison.register_garrison_intent).
func _notification(a_what: int) -> void:
	if a_what == NOTIFICATION_PREDELETE and message != null and is_instance_valid(message.target):
		var target := message.target as Commandable
		if target != null and target.movement != null:
			target.movement.restore_avoidance_layers()
	super._notification(a_what)


#endregion


#region Debug
func _to_string() -> String:
	return "Occupy: %s" % message.position
#endregion
