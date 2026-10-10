class_name AlertThrottle
extends RefCounted
## WHICH RAISED ALERTS ONE COMMANDER IS ACTUALLY SHOWN. One throttle per viewer, so one player's
## flood never silences another's.
##
## Two rules, chosen per alert type by AlertCatalog:
##
## SPATIAL (a type with a `group`) — 0 A.D.'s AttackDetection. An admitted alert opens a HOLD at
## its position for `suppress_seconds`. A later alert of the same group inside `suppress_radius`
## of a hold is swallowed; if it is also inside `transfer_radius` it MOVES the hold to itself and
## restarts its clock, so one fight that drifts across the map stays one alert. A swallowed alert
## of HIGHER priority breaks through instead: it is admitted and replaces the hold (units under
## attack, then the base behind them).
##
## KEYED (no group) — one hold per (type, key) for `suppress_seconds`: the same superweapon
## coming ready twice inside ten seconds is said once. A zero time admits everything.
##
## Unlocated alerts of a grouped type fall back to the keyed rule. gdd/systems/ux/ui/alerts.md
## §Throttling.

#region Properties
## group → Array of holds {position: Vector2, tick: int, priority: int, type: Type}
var _holds_by_group: Dictionary = {}
## Vector2i(type, key) → tick the keyed hold expires
var _keyed_until: Dictionary = {}
#endregion


#region Public API
## Whether `a_alert` is shown. Updates the holds either way; call once per raised alert, in
## raise order, with the alert's own tick as "now".
func admit(a_alert: Alert) -> bool:
	var group: StringName = AlertCatalog.group_of(a_alert.type)
	if group != &"" and a_alert.has_position:
		return _admit_spatial(a_alert, group)
	return _admit_keyed(a_alert)


## Forget every hold — the viewer changed (play_as / spectate), so nothing it was shown is
## the new viewer's.
func clear() -> void:
	_holds_by_group.clear()
	_keyed_until.clear()


#endregion


#region Private helpers
func _admit_spatial(a_alert: Alert, a_group: StringName) -> bool:
	var now: int = a_alert.tick
	var holds: Array = _holds_by_group.get(a_group, [])
	holds = holds.filter(
		func(h: Dictionary) -> bool:
			return now - int(h["tick"]) < AlertCatalog.suppress_ticks(h["type"])
	)
	_holds_by_group[a_group] = holds

	var here: Vector2 = a_alert.xz()
	var priority: int = AlertCatalog.priority_of(a_alert.type)
	var fresh: Dictionary = {
		"position": here, "tick": now, "priority": priority, "type": a_alert.type
	}
	var radius: float = AlertCatalog.suppress_radius(a_alert.type)
	var transfer: float = AlertCatalog.transfer_radius(a_alert.type)
	for i: int in holds.size():
		var hold: Dictionary = holds[i]
		var distance: float = here.distance_to(hold["position"])
		if distance >= radius:
			continue
		if priority > int(hold["priority"]):
			holds[i] = fresh
			return true
		if priority == int(hold["priority"]) and distance < transfer:
			holds[i] = fresh
		return false
	holds.append(fresh)
	return true


func _admit_keyed(a_alert: Alert) -> bool:
	var ticks: int = AlertCatalog.suppress_ticks(a_alert.type)
	if ticks <= 0:
		return true
	var slot := Vector2i(int(a_alert.type), a_alert.key)
	if a_alert.tick < int(_keyed_until.get(slot, -1)):
		return false
	_keyed_until[slot] = a_alert.tick + ticks
	return true
#endregion
