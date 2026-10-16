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
	actor: Actor, _message: CommandMessage
) -> PreconditionFailureCause:
	var deployable: Deployable = Deployable.of(actor)
	if deployable == null or deployable.stance != Deployable.Stance.DEPLOYED:
		return PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
	return PreconditionFailureCause.NONE


#endregion


#region State updates
## Never swapped for anything else: a transition is not interrupted by aggro.
func get_updated_state(_a_actor: Actor) -> Variant:
	return self


func should_move(_a_actor: Actor) -> bool:
	return false


## Whether the undeploy has run its time, as this tick's apply_state found.
var _is_finished: bool = false


## Starts the undeploy on its first tick and runs it a tick each tick after.
func apply_state(a_actor: Actor) -> void:
	var deployable: Deployable = Deployable.of(a_actor)
	if deployable == null:
		_is_finished = true
	elif deployable.stance == Deployable.Stance.DEPLOYED and not deployable.begin_undeploy():
		_is_finished = true
	else:
		_is_finished = deployable.advance()


## True once the undeploy has run its time.
func can_act(_a_actor: Actor) -> bool:
	return _is_finished


func fulfill_action(_a_actor: Actor) -> Variant:
	return null


## Dropped before it finished — only the actor's teardown does that — so the actor keeps
## its deployed stance.
func on_released(a_actor: Actor) -> void:
	var deployable: Deployable = Deployable.of(a_actor)
	if deployable != null and deployable.stance == Deployable.Stance.UNDEPLOYING:
		deployable.abandon_transition()


#endregion


#region Debug
func _to_string() -> String:
	return "Undeploy"
#endregion
