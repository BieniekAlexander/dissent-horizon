class_name OrdnanceArsenal extends RefCounted

## A commander's per-match ordnance state, built from its Faction's ordnance DAG
## (Faction.ordnance_unlocks). Each OrdnanceUnlock is wrapped in an Entry that tracks
## whether this commander owns it yet and holds a live, duplicated Ordnance instance
## so cooldowns are per-commander.
##
## Unlocking spends dominion and is gated by the DAG: an entry becomes available once
## ANY of its prerequisites is owned (or it has none). The OrdnanceUnlock templates
## are shared, read-only authored data; all mutable ownership state lives here.

## One DAG node plus this commander's ownership state for it.
class Entry:
	var unlock: OrdnanceUnlock  ## shared authored template (cost, prerequisites)
	var ordnance: Ordnance      ## live per-commander instance (duplicated)
	var owned: bool = false

var _commander: Commander
## DAG nodes in authored order — the UI renders one button per entry.
var entries: Array[Entry] = []
var _by_unlock: Dictionary = {}  ## OrdnanceUnlock -> Entry, for prerequisite lookups


func _init(a_commander: Commander, unlocks: Array) -> void:
	_commander = a_commander
	for unlock: OrdnanceUnlock in unlocks:
		if unlock == null or unlock.ordnance == null:
			continue
		var entry := Entry.new()
		entry.unlock = unlock
		entry.ordnance = unlock.ordnance.duplicate()
		entries.append(entry)
		_by_unlock[unlock] = entry


## True when `entry` can be unlocked next: not yet owned and its any-of prerequisites
## are satisfied (a node with no prerequisites is always available).
func is_available(entry: Entry) -> bool:
	if entry.owned:
		return false
	if entry.unlock.prerequisites.is_empty():
		return true
	return entry.unlock.prerequisites.any(func(p: OrdnanceUnlock): return _owns(p))


## True when the commander has the dominion to pay for `entry`.
func can_afford(entry: Entry) -> bool:
	return _commander.dominion >= entry.unlock.dominion_cost


## Attempt to unlock `entry`: it must be available and affordable. On success, spends
## the dominion and marks it owned. Returns whether it unlocked.
func try_unlock(entry: Entry) -> bool:
	if not is_available(entry) or not can_afford(entry):
		return false
	_commander.add_dominion(-entry.unlock.dominion_cost)
	entry.owned = true
	return true


## The live Ordnance instances for owned entries — what can actually be deployed.
func owned_ordnances() -> Array[Ordnance]:
	var out: Array[Ordnance] = []
	for entry: Entry in entries:
		if entry.owned:
			out.append(entry.ordnance)
	return out


func _owns(unlock: OrdnanceUnlock) -> bool:
	var entry: Entry = _by_unlock.get(unlock)
	return entry != null and entry.owned
