@tool
class_name ConditionAlways
extends Condition

## Always true — the stand-in a GlobalTrigger watches when no conditions were authored on it.
##
## A trigger with nothing to wait for should fire as soon as it arms; the alternative (never
## firing) makes such a trigger indistinguishable from one that doesn't exist. But `fire()` is
## only ever reached from a Condition's state_changed, so "no conditions" needs SOMETHING to
## drive it — this is that something, supplied by GlobalTrigger._watched() rather than
## authored. It is an ordinary PULL condition, so it registers with the ConditionPoller like
## any other and reports its rising edge on the first physics frame after arming: exactly the
## timing a ConditionTimer with a zero interval used to give, and late enough that Scenario has
## finished building its commanders.
##
## Authoring one explicitly is legal and means the same thing. It is simply never necessary.


#region Public API
func evaluate(_a_manager: ScenarioTriggerManager) -> bool:
	return true
#endregion
