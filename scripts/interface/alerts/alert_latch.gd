class_name AlertLatch
extends RefCounted
## WHEN A STATE ALERT SPEAKS. A state ("energy is piling up") is polled, not signalled, and
## would otherwise speak on every poll. The latch speaks once the state has held for
## `sustain` ticks, then every `repeat` ticks while it keeps holding, and resets the moment it
## stops — so a state that flickers shorter than `sustain` never speaks at all.
##
## Hysteresis on the condition itself (enter at one level, leave at a lower one) is the
## caller's, since only the caller knows the levels. gdd/systems/ux/ui/alerts.md §State alerts.

#region Properties
var sustain_ticks: int = 0
## 0 = say it once per episode and never remind.
var repeat_ticks: int = 0

## Tick the state started holding, or -1 while it does not.
var _since: int = -1
## Tick it last spoke this episode, or -1 if it has not yet.
var _spoke_at: int = -1
#endregion


#region Lifecycle
func _init(a_sustain_ticks: int = 0, a_repeat_ticks: int = 0) -> void:
	sustain_ticks = a_sustain_ticks
	repeat_ticks = a_repeat_ticks


#endregion


#region Public API
## Feed the state's value at tick `a_now`. True when the alert should be raised now.
func update(a_holds: bool, a_now: int) -> bool:
	if not a_holds:
		_since = -1
		_spoke_at = -1
		return false
	if _since < 0:
		_since = a_now
	if a_now - _since < sustain_ticks:
		return false
	if _spoke_at < 0 or (repeat_ticks > 0 and a_now - _spoke_at >= repeat_ticks):
		_spoke_at = a_now
		return true
	return false


func is_holding() -> bool:
	return _since >= 0
#endregion
