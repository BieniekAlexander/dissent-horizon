class_name Deploy
extends MoveCommand

## Plant the actor where it stands (see Deployable). The command IS the transition: it holds
## the actor until the deploy has run its time, then ends. The rules:
## gdd/systems/commands/deploying.md.


#region Preconditions
static func requires_position() -> bool:
	return false


## Valid for a Deployable piece that is MOBILE — a deployed or transitioning one is a no-op,
## which is what lets a mixed selection deploy only the ones still standing up.
static func meets_precondition(
	actor: Actor, _message: CommandMessage
) -> PreconditionFailureCause:
	var deployable: Deployable = Deployable.of(actor)
	if deployable == null or deployable.stance != Deployable.Stance.MOBILE:
		return PreconditionFailureCause.UNENUMERATED_FAILURE_CAUSE
	return PreconditionFailureCause.NONE


#endregion


#region State updates
## Never swapped for anything else: a transition is not interrupted by aggro.
func get_updated_state(_a_actor: Actor) -> Variant:
	return self


func should_move(_a_actor: Actor) -> bool:
	return false


## Whether the deploy has run its time, as this tick's apply_state found.
var _is_finished: bool = false


## Starts the deploy on its first tick and runs it a tick each tick after.
func apply_state(a_actor: Actor) -> void:
	var deployable: Deployable = Deployable.of(a_actor)
	if deployable == null:
		_is_finished = true
	elif deployable.stance == Deployable.Stance.MOBILE and not deployable.begin_deploy():
		_is_finished = true
	else:
		_is_finished = deployable.advance()


## True once the deploy has run its time.
func can_act(_a_actor: Actor) -> bool:
	return _is_finished


func fulfill_action(_a_actor: Actor) -> Variant:
	return null


## Dropped before it finished — only an order that cancels a cancellable deploy, or the
## actor's teardown, does that — so the actor stands back up.
func on_released(a_actor: Actor) -> void:
	var deployable: Deployable = Deployable.of(a_actor)
	if deployable != null and deployable.stance == Deployable.Stance.DEPLOYING:
		deployable.abandon_transition()


#endregion


#region Debug
func _to_string() -> String:
	return "Deploy"
#endregion
