class_name ConditionNoPendingTriggers
extends Condition

## True once this is the only trigger still active in the manager — i.e. every
## other trigger has already fired (one-shot) or been disabled. Models the
## "no more events are waiting to be processed" gate.
##
## Zero-config by design: it queries the manager rather than referencing other
## triggers, so it can't drift out of sync with the trigger list as waves are
## added or removed. Pair it (AND) with the real win/loss check so victory isn't
## declared before the scenario's other beats have played out.
##
## Note: a never-disabling repeating trigger keeps the active count above one
## forever, so this condition would never pass alongside one. That matches the
## intent — a perpetual trigger genuinely is "still waiting."

#region Public API
func evaluate(manager: ScenarioEventManager) -> bool:
	return manager.active_trigger_count() <= 1
#endregion
