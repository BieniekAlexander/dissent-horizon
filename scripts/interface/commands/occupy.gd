class_name Occupy
extends Command

#region Preconditions
static func requires_position() -> bool:
	return true

## Valid when:
##   - the target is a Commandable that owns a Garrison component and is either
##     of the actor's own commander OR commanderless (neutral, id 0)
##   - the acting unit's Movement mode is GROUNDED_DIRECT
static func meets_precondition(
	a_actor: Commandable,
	a_message: CommandMessage
) -> PreconditionFailureCause:
	if not is_instance_valid(a_message.target) or not (a_message.target is Commandable):
		return PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
	# A garrison-capable unit cannot occupy itself.
	if a_message.target == a_actor:
		return PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
	if not a_message.target.has_node("Garrison"):
		return PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
	if not (a_message.target as Commandable).is_built:
		return PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
	if a_actor.movement == null or a_actor.movement.mode != Movement.Mode.GROUNDED_DIRECT:
		return PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
	# Own-team garrisons and commanderless (neutral) garrisons are both occupiable;
	# an enemy-held garrison is not.
	var target_commander_id: int = (a_message.target as Commandable).commander_id
	if target_commander_id != a_actor.commander_id and target_commander_id != 0:
		return PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
	return PreconditionFailureCause.NONE
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
	if is_instance_valid(a_actor) and is_instance_valid(message.target) \
			and message.target is CollisionObject3D:
		a_actor.add_collision_exception_with(message.target)
		_excluded_actor = a_actor

## Restore normal collision between the actor and the target. Safe to call
## multiple times and when either node is already gone.
func _clear_collision_exception() -> void:
	if is_instance_valid(_excluded_actor) and is_instance_valid(message.target) \
			and message.target is CollisionObject3D:
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
func get_updated_state(a_actor: Commandable) -> Command:
	if not is_instance_valid(message.target):
		_clear_collision_exception()
		_clear_rvo_suppression()
		return null
	_ensure_collision_exception(a_actor)
	_ensure_rvo_suppression(a_actor)
	var host := message.target as Commandable
	if host != null and host.movement != null \
			and host.movement.mode == Movement.Mode.HOVERING \
			and host.garrison != null \
			and _garrison_registered_actor == null:
		host.garrison.register_garrison_intent(a_actor)
		_garrison_registered_actor = a_actor
	return self

## While the host is a HOVERING unit that has not yet grounded, keep approaching
## unconditionally so the actor tracks the host's moving XZ position.
## Once grounded, fall back to the normal proximity check.
func should_move(a_actor: Commandable) -> bool:
	if not is_instance_valid(message.target):
		return false
	var host := message.target as Commandable
	if host != null and host.movement != null \
			and host.movement.mode == Movement.Mode.HOVERING \
			and not host.movement.is_grounded_temp():
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
	if garrison == null or not garrison.can_garrison():
		return false
	var host := message.target as Commandable
	if host != null and host.movement != null \
			and host.movement.mode == Movement.Mode.HOVERING \
			and not host.movement.is_grounded_temp():
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
	if host != null and host.movement != null \
			and host.movement.mode == Movement.Mode.HOVERING:
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
## Safety net: if this command is replaced by another (e.g. the player issues a
## new order mid-approach) it is freed without any explicit completion call, so
## drop both exceptions here too rather than leaking them. Inlined (rather than
## calling the helper methods) because during PREDELETE the script instance is
## mid-teardown and dispatching to other methods fails.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if is_instance_valid(_excluded_actor) and message != null \
				and is_instance_valid(message.target) and message.target is CollisionObject3D:
			_excluded_actor.remove_collision_exception_with(message.target)
		_excluded_actor = null
		if is_instance_valid(_rvo_suppressed_actor) and _rvo_suppressed_actor.movement != null:
			_rvo_suppressed_actor.movement.restore_avoidance_layers()
		_rvo_suppressed_actor = null
		if message != null and is_instance_valid(message.target):
			var target := message.target as Commandable
			if target != null and target.movement != null:
				target.movement.restore_avoidance_layers()
			# If this actor registered garrison intent but never actually garrisoned
			# (e.g. the player issued a new command), unregister now so the host
			# doesn't stay grounded waiting for a unit that has moved on.
			if _garrison_registered_actor != null and target != null \
					and target.garrison != null:
				target.garrison.unregister_garrison_intent(_garrison_registered_actor)
		_garrison_registered_actor = null
	super._notification(what)
#endregion

#region Debug
func _to_string() -> String:
	return "Occupy: %s" % message.position
#endregion
