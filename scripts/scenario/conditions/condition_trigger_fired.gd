@tool
class_name ConditionTriggerFired
extends Condition

## True once a named GlobalTrigger has fired — "the prisoners are free", read by anything that
## needs to know a beat has happened. Its first use is a ScenarioTactic rule: a rule takes ONE
## condition, so a squad that changes what it does when a beat lands reads that beat's trigger,
## and the trigger is where the beat's several conditions are combined (Alex, 2026-10-18,
## prologue mission 1's ally squad). A prerequisite does the same between two triggers; this is
## that, for everything that is not a trigger.
##
## A PULL condition. The trigger is found by NAME anywhere under the manager, so a trigger moved
## within the tree keeps working; renaming it breaks the check, which is reported once.

#region Properties
## Node name of the GlobalTrigger to watch.
@export var trigger_name: String = ""

var _watched: GlobalTrigger = null
var _resolved: bool = false
#endregion


#region Public API
func evaluate(a_manager: ScenarioTriggerManager) -> bool:
	_resolve(a_manager)
	return _watched != null and is_instance_valid(_watched) and _watched.has_fired


func reset() -> void:
	super.reset()
	_watched = null
	_resolved = false


#endregion


#region Private helpers
func _resolve(a_manager: ScenarioTriggerManager) -> void:
	if _resolved:
		return
	_resolved = true
	if not trigger_name.is_empty():
		_watched = a_manager.find_child(trigger_name, true, false) as GlobalTrigger
	if _watched == null:
		push_warning(
			(
				(
					"ConditionTriggerFired: no GlobalTrigger named '%s' under the manager. "
					% trigger_name
				)
				+ "This check can never become true; did the trigger get renamed?"
			)
		)
#endregion
