class_name Undeploy
extends MoveCommand

## Stand a deployed actor back up (see Deployable). The command IS the transition: it holds
## the actor until the undeploy has run its time, then ends. The rules:
## gdd/systems/commands/deploying.md.

#region Preconditions
static func requires_position() -> bool:
	return false

## Valid for a Deployable piece that is DEPLOYED — any other is a no-op.
static func meets_precondition(
	actor: Commandable,
	_message: CommandMessage
) -> PreconditionFailureCause:
	var deployable: Deployable = Deployable.of(actor)
	if deployable == null or deployable.stance != Deployable.Stance.DEPLOYED:
		return PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
	return PreconditionFailureCause.NONE
#endregion

#region State updates
## Never swapped for anything else: a transition is not interrupted by aggro.
func get_updated_state(_a_actor: Commandable) -> Variant:
	return self

func should_move(_a_actor: Commandable) -> bool:
	return false

## Starts the undeploy on its first tick and reports true once it has run its time.
func can_act(a_actor: Commandable) -> bool:
	var deployable: Deployable = Deployable.of(a_actor)
	if deployable == null:
		return true
	if deployable.stance == Deployable.Stance.DEPLOYED and not deployable.begin_undeploy():
		return true
	return deployable.advance()

func fulfill_action(_a_actor: Commandable) -> Variant:
	return null

## Dropped before it finished — only the actor's teardown does that — so the actor keeps
## its deployed stance.
func on_released(a_actor: Commandable) -> void:
	var deployable: Deployable = Deployable.of(a_actor)
	if deployable != null and deployable.stance == Deployable.Stance.UNDEPLOYING:
		deployable.abandon_transition()
#endregion

#region Debug
func _to_string() -> String:
	return "Undeploy"
#endregion
