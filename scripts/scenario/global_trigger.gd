@tool
class_name GlobalTrigger
extends Node

## A scenario-wide ("global") Trigger: it owns a set of Conditions and, as inline child
## nodes, the AbstractEvents it runs when they're met. Rather than being polled, it ARMS
## its conditions (arm()) and fires reactively when a condition reports a change
## (Condition.state_changed) and the AND/OR aggregate crosses into satisfied. Each
## condition picks its own driver — push conditions ride a bus, pull conditions are ticked
## by the manager's ConditionPoller — but the trigger doesn't care which.
##
## On fire it runs each child AbstractEvent in place via ScenarioTriggerManager.run_event.
## Because the events live in this scene, their authored world positions (e.g. an
## EventSpawnEntities node, an EventCommandPoint) are used directly — that's how you point
## a global trigger at a location in the game world.
##
## Add these as children of a ScenarioTriggerManager, each with its own child events.

#region Properties
enum ConditionMode {
	## All conditions must be true to fire.
	AND,
	## Any one condition being true fires.
	OR
}

## Human-readable label shown in the inspector and debug output.
@export var label: String = ""
@export var conditions: Array[Condition] = []
@export var condition_mode: ConditionMode = ConditionMode.AND

## When true the trigger disables itself after firing once.
@export var one_shot: bool = true
## When true the trigger starts inactive; re-enable it via EventChainTrigger.
@export var starts_disabled: bool = false

## Runtime state — not serialized. Whether this trigger is currently watching. Set from
## starts_disabled by ScenarioTriggerManager._ready(); toggled by set_active().
var enabled: bool = true

## The manager this trigger is armed against; null until armed.
var _manager: ScenarioTriggerManager
## Last aggregate satisfaction, for rising-edge firing.
var _was_satisfied: bool = false
#endregion

#region Arming
## Subscribe to this trigger's conditions so it fires reactively when they become
## satisfied — no per-tick polling of the trigger itself. Each condition arms its own
## driver (push: a bus; pull: the ConditionPoller); we re-check on its state_changed.
func arm(manager: ScenarioTriggerManager) -> void:
	_manager = manager
	_was_satisfied = false
	for condition: Condition in conditions:
		condition.arm(manager)
		if not condition.state_changed.is_connected(_on_condition_changed):
			condition.state_changed.connect(_on_condition_changed)


## Undo arm(): disconnect from the conditions and let them tear down their drivers.
func disarm() -> void:
	if _manager == null:
		return
	for condition: Condition in conditions:
		if condition.state_changed.is_connected(_on_condition_changed):
			condition.state_changed.disconnect(_on_condition_changed)
		condition.disarm(_manager)


## Enable/disable at runtime (EventChainTrigger). Arms a re-enabled trigger and disarms
## a disabled one. `manager` may be null when no manager is wired (e.g. a unit test just
## flipping the flag), in which case only the flag changes.
func set_active(active: bool, manager: ScenarioTriggerManager) -> void:
	enabled = active
	if manager == null:
		return
	if active:
		arm(manager)
	else:
		disarm()
#endregion

#region Firing
## Re-check on a condition's state_changed and fire on the rising edge of the AND/OR
## aggregate. Reads each condition's cached truth (Condition.is_met) rather than
## re-evaluating, so a side-effecting evaluate() runs at most once per frame (in poll()).
func _on_condition_changed() -> void:
	if not enabled:
		return
	var now: bool = _aggregate_met()
	if now == _was_satisfied:
		return
	_was_satisfied = now
	if now:
		fire(_manager)


## AND/OR aggregate over the conditions' cached truth (is_met). Empty => never fires.
func _aggregate_met() -> bool:
	if conditions.is_empty():
		return false
	if condition_mode == ConditionMode.AND:
		return conditions.all(func(c: Condition) -> bool: return c.is_met())
	return conditions.any(func(c: Condition) -> bool: return c.is_met())


## Live AND/OR aggregate over evaluate() — the direct query API (and what tests use).
## The firing path uses the cached _aggregate_met() instead, to avoid re-evaluating.
func is_satisfied(manager: ScenarioTriggerManager) -> bool:
	if conditions.is_empty():
		return false
	if condition_mode == ConditionMode.AND:
		return conditions.all(func(c: Condition) -> bool: return c.evaluate(manager))
	return conditions.any(func(c: Condition) -> bool: return c.evaluate(manager))


func fire(manager: ScenarioTriggerManager) -> void:
	# Run each inline child AbstractEvent in place (source = null: a global trigger isn't
	# tied to an entity). Events use their own authored positions.
	for child in get_children():
		if child is AbstractEvent:
			manager.run_event(child as AbstractEvent, null)
	if one_shot:
		enabled = false
		disarm()
	else:
		# Repeating: reset conditions and the edge latch so the next rising edge re-fires.
		_was_satisfied = false
		for condition: Condition in conditions:
			condition.reset()
#endregion
