class_name ConditionPoller
extends Node

## Drives PULL-based Conditions. Every physics frame it re-checks each registered
## Condition (via Condition.poll → evaluate), so conditions that can't announce their
## own changes — live state checks like ConditionUnitCount or ConditionUnitsInRegion —
## still nudge their owning GlobalTrigger on a truth edge. PUSH conditions never register
## here; they ride signal buses instead. Owned/created by ScenarioTriggerManager._ready.

var manager: ScenarioTriggerManager

var _conditions: Array[Condition] = []


#region Registration
func add(a_condition: Condition) -> void:
	if a_condition not in _conditions:
		_conditions.append(a_condition)


func remove(a_condition: Condition) -> void:
	_conditions.erase(a_condition)


#endregion


#region Lifecycle
func _physics_process(_a_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	# Iterate a COPY. poll() can fire its owning trigger inline, and a one-shot trigger disarms
	# itself while firing — which calls remove() on this very array. Walking the live array
	# would shift the remaining entries left mid-loop, so the condition sitting immediately
	# after each one that fires gets SKIPPED for that tick: two triggers coming due on the same
	# tick would run only the first. For a sticky condition (a countdown) that reads as a
	# one-tick delay, but for a transient one (a unit count true for a single tick) the missed
	# poll is the only edge there was, and the trigger never fires at all.
	for condition: Condition in _conditions.duplicate():
		# Re-check membership: an earlier trigger this tick may have deliberately disarmed this
		# condition (a one-shot firing, an EventChainTrigger switching a trigger off), and a
		# condition that has been removed should not still be evaluated afterwards.
		if _conditions.has(condition):
			condition.poll(manager)
#endregion
