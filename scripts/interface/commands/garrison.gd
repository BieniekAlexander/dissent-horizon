class_name Garrison
extends Command

## PRECONDITIONS

static func requires_position() -> bool:
	return true

## Valid when:
##   - the target is a friendly Commandable that owns a Shelter component
##   - the acting unit's Movement mode is DEFAULT
static func meets_precondition(
	a_actor: Commandable,
	a_message: CommandMessage
) -> PreconditionFailureCause:
	if not is_instance_valid(a_message.target) or not (a_message.target is Commandable):
		return PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
	# A shelter-capable unit cannot garrison into itself.
	if a_message.target == a_actor:
		return PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
	if not a_message.target.has_node("Shelter"):
		return PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
	if a_actor.movement == null or a_actor.movement.mode != Movement.Mode.DEFAULT:
		return PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
	if (a_message.target as Commandable).commander_id != a_actor.commander_id:
		return PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
	return PreconditionFailureCause.NONE


## STATE UPDATES

## The actor that currently holds a MOVEMENT_OBSTRUCTION collision exception
## against the target, so we know whose exception to clear on teardown.
var _excluded_actor: Commandable = null

## While approaching, the actor would physically collide with the target's
## MOVEMENT_OBSTRUCTION body — stopping it short of garrison range (and tripping
## the slide-collision command-cancel in Commandable._on_velocity_computed).
## Exclude the target's body so the actor can move right up to / into it.
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

## Cancel if the target is destroyed while the unit is en route.
func get_updated_state(a_actor: Commandable) -> Command:
	if not is_instance_valid(message.target):
		_clear_collision_exception()
		return null
	_ensure_collision_exception(a_actor)
	return self

## Move until adjacent to the shelter structure.
func should_move(a_actor: Commandable) -> bool:
	return is_instance_valid(message.target) \
		and not SU.unit_is_close_to_target(a_actor, message.target)

## Garrison once adjacent and the shelter still has room.
func can_act(a_actor: Commandable) -> bool:
	if not is_instance_valid(message.target):
		return false
	if not SU.unit_is_close_to_target(a_actor, message.target):
		return false
	var shelter := message.target.get_node_or_null("Shelter") as Shelter
	return shelter != null and shelter.can_garrison()

## Remove the acting unit from the scene tree into the shelter.
func fulfill_action(a_actor: Commandable) -> Variant:
	# Clear the exception before garrisoning — once garrisoned the actor leaves
	# the tree, so do the bookkeeping while its body is still resolvable.
	_clear_collision_exception()
	var shelter := message.target.get_node_or_null("Shelter") as Shelter
	if shelter != null:
		shelter.garrison(a_actor)
	return null


## Safety net: if this command is replaced by another (e.g. the player issues a
## new order mid-approach) it is freed without any explicit completion call, so
## drop the collision exception here too rather than leaking it. Inlined (rather
## than calling _clear_collision_exception) because during PREDELETE the script
## instance is mid-teardown and dispatching to another method fails.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if is_instance_valid(_excluded_actor) and message != null \
				and is_instance_valid(message.target) and message.target is CollisionObject3D:
			_excluded_actor.remove_collision_exception_with(message.target)
		_excluded_actor = null
	super._notification(what)


## DEBUG
func _to_string() -> String:
	return "Garrison: %s" % message.position
