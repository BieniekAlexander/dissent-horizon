class_name Condition
extends Resource

## A boolean check on game state, owned by a GlobalTrigger. A Condition may be PULL- or
## PUSH-based, and which one is entirely the subclass's choice — the owning trigger
## consumes both identically:
##   * PULL: override evaluate() to compute truth live from game state. The DEFAULT
##     arm() registers the condition with the ScenarioTriggerManager's ConditionPoller,
##     which calls poll() every physics frame and emits state_changed on a truth edge.
##   * PUSH: override arm()/disarm() to (dis)connect a signal bus (e.g.
##     ScenarioTriggerManager.entity_occurrence), update truth in the handler, and emit
##     state_changed yourself. evaluate() then just reports the cached result.
## Either way evaluate() must be idempotent — it may be called more than once.

## Emitted when this condition's truth changes — the cue for an owning GlobalTrigger to
## re-check and (on a rising edge) fire. Named state_changed, not `changed`, to avoid
## colliding with Resource's built-in `changed` signal.
signal state_changed

#region Public API
## Current truth, computed live. PULL subclasses inspect game state here; PUSH
## subclasses return cached state maintained by their bus handler. Must be idempotent.
func evaluate(_manager: ScenarioTriggerManager) -> bool:
	return false

## Cached truth — the last value seen by poll() or a push handler. The owning trigger
## aggregates THIS rather than re-calling evaluate(), so a side-effecting evaluate()
## runs at most once per frame (inside poll()).
func is_met() -> bool:
	return _last

## Subscribe to whatever drives this condition. DEFAULT = pull: register with the
## manager's ConditionPoller. PUSH subclasses override to connect a bus instead.
func arm(manager: ScenarioTriggerManager) -> void:
	manager.condition_poller.add(self)

## Undo arm(). DEFAULT = pull: deregister from the poller. PUSH subclasses override to
## disconnect their bus.
func disarm(manager: ScenarioTriggerManager) -> void:
	manager.condition_poller.remove(self)

## Called when the owning GlobalTrigger resets after firing (repeating triggers only).
## Override to clear per-fire state, and call super() to keep edge tracking consistent.
func reset() -> void:
	_last = false
#endregion

#region Pull plumbing
## Last truth seen, for edge detection and is_met().
var _last: bool = false

## Edge-detected re-check, called once per physics frame by the ConditionPoller for pull
## conditions. Updates the cache and emits state_changed only on a transition — a steady
## condition costs one evaluate() per frame and nudges the trigger only on change.
func poll(manager: ScenarioTriggerManager) -> void:
	var now: bool = evaluate(manager)
	if now != _last:
		_last = now
		state_changed.emit()
#endregion
