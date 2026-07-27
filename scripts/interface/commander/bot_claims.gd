class_name BotClaims
extends RefCounted

## WHO IN THE BOT OWNS A UNIT RIGHT NOW — one registry per bot, shared by every manager.
##
## The managers run on independent periods (see BotScheduler), so "the scout ran before the
## military this tick" no longer protects a scout from being swept into the army. Ownership is
## stated here instead: a manager that tasks a unit claims it, the others leave claimed units
## alone, and the owner releases it when its errand ends. A unit nobody has claimed is the
## ARMY's — BotMilitary never claims, it takes what is left.
##
## A claim may be TAKEN by a higher-priority owner (combat over scouting); the previous owner
## notices on its next run that `owns` has gone false. See
## gdd/systems/ai/think-scheduling.md §Decision 3.

## How strongly an owner holds a unit. A claim can only be taken by a strictly higher level;
## equal levels never take from each other, which is what keeps two errands (a build job and a
## deposit run) from stealing a unit back and forth.
enum Priority {
	## Out looking at the map. The weakest claim: any real job outranks it.
	SCOUT = 1,
	## Engaging a specific threat (BotTargeting). Outranks scouting, and is what keeps the army's
	## rally from overriding a unit mid-fight.
	COMBAT = 2,
	## On a job that must run to completion: construction, a capture or deposit, liberation.
	ERRAND = 3,
	## Under a manager with sole say over it (BotKamikaze's drones).
	EXCLUSIVE = 4,
}

## instance id -> {"owner": StringName, "priority": int}. Keyed by id so a freed unit's claim
## can be dropped without touching the dead reference.
var _claims: Dictionary = {}


## Claim `a_unit` for `a_owner`. True when the owner holds it afterwards: it was unclaimed,
## already this owner's, or held at a strictly lower priority.
func claim(a_unit: Commandable, a_owner: StringName, a_priority: Priority) -> bool:
	if not can_claim(a_unit, a_owner, a_priority):
		return false
	_claims[a_unit.get_instance_id()] = {"owner": a_owner, "priority": a_priority}
	return true


## Whether `claim` would succeed, without claiming.
func can_claim(a_unit: Commandable, a_owner: StringName, a_priority: Priority) -> bool:
	var held: Variant = _live_claim(a_unit.get_instance_id())
	return held == null or held["owner"] == a_owner or int(held["priority"]) < a_priority


## Give `a_unit` back, if `a_owner` still holds it. A no-op for a unit someone else has taken.
func release(a_unit: Variant, a_owner: StringName) -> void:
	if not is_instance_valid(a_unit):
		return
	var key: int = (a_unit as Object).get_instance_id()
	var held: Variant = _live_claim(key)
	if held != null and held["owner"] == a_owner:
		_claims.erase(key)


## True when `a_owner` holds `a_unit`. Untyped so a freed unit answers false rather than
## failing the typed-parameter check (CLAUDE.md §A freed object cannot be passed to a typed
## parameter).
func owns(a_unit: Variant, a_owner: StringName) -> bool:
	if not is_instance_valid(a_unit):
		return false
	var held: Variant = _live_claim((a_unit as Object).get_instance_id())
	return held != null and held["owner"] == a_owner


## True when anybody has claimed `a_unit` — i.e. it is not the army's to take.
func is_claimed(a_unit: Commandable) -> bool:
	return _live_claim(a_unit.get_instance_id()) != null


## Who holds `a_unit`, or &"" when nobody does.
func owner_of(a_unit: Commandable) -> StringName:
	var held: Variant = _live_claim(a_unit.get_instance_id())
	return held["owner"] if held != null else &""


## Every unit `a_owner` currently holds.
func units_of(a_owner: StringName) -> Array:
	var out: Array = []
	for key: int in _claims.keys():
		var held: Variant = _live_claim(key)
		if held != null and held["owner"] == a_owner:
			out.append(instance_from_id(key))
	return out


## The claim on instance `a_key`, or null — dropping it first if the unit has been freed.
func _live_claim(a_key: int) -> Variant:
	if not _claims.has(a_key):
		return null
	if not is_instance_id_valid(a_key):
		_claims.erase(a_key)
		return null
	return _claims[a_key]
