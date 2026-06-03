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
	if not a_message.target.has_node("Shelter"):
		return PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
	if a_actor.movement == null or a_actor.movement.mode != Movement.Mode.DEFAULT:
		return PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
	if (a_message.target as Commandable).commander_id != a_actor.commander_id:
		return PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
	return PreconditionFailureCause.NONE


## STATE UPDATES

## Cancel if the target is destroyed while the unit is en route.
func get_updated_state(a_actor: Commandable) -> Command:
	return self if is_instance_valid(message.target) else null

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
	var shelter := message.target.get_node_or_null("Shelter") as Shelter
	if shelter != null:
		shelter.garrison(a_actor)
	return null


## DEBUG
func _to_string() -> String:
	return "Garrison: %s" % message.position
