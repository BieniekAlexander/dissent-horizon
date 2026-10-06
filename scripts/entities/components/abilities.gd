class_name Abilities
extends Node

## What abilities this piece can use, and the CHARGES they draw on.
##
## THE CHARGE IS THE UNIVERSAL UNIT. Every ability is charge-based — there is deliberately
## no way to express one that is not. An ability that is "just a cooldown" is a pool of
## ONE charge: it is spent on use and comes back after the cooldown, which is the same
## mechanic with max_charges = 1 rather than a second, parallel concept. That is why
## `PreconditionFailureCause.ABILITY_NO_CHARGES` can speak for every ability in the game.
##
## ABILITIES ARE GROUPED INTO POOLS, and abilities in one pool SHARE it. An Operations
## Center that scans, promotes, freezes and drops beacons has one pool of one charge: use
## any of the four and all four go down together until it recharges. A piece whose
## abilities are independent lists them as separate one-entry pools. So sharing is
## expressed by grouping rather than by a flag, and the default (one ability, one pool) is
## the same shape as the interesting case.
##
## DECLARED ON THE PIECE, not on the ability. An ability may be usable by several kinds of
## piece — C&C Generals' Demolition General gives nearly his whole army the same demolition
## charge — and a piece is the thing that knows what it can do and how its own charges
## work. It also lets two pieces grant the SAME ability with different charges and
## cooldowns, which naming the caster on the ability could not express.

## CAPACITY AND STARTING STOCK ARE SEPARATE. `max_charges` is how many the pool holds;
## `initial_charges` is how many a freshly-built piece has in it, and defaults to a full
## pool. They are distinct because "how powerful is this ability" and "does it come online
## armed or does the owner wait out one cooldown first" are different balance questions —
## a battery that must spin up before its first shot is `initial_charges: 0`, and no value
## of a single `charges` key could say that.

## The authored pools. Each is
## `{"initial_charges": int, "max_charges": int, "cooldown_ticks": int, "grants": Array}`,
## written by the spec importer from the piece doc's `abilities:`.
##
## An Array[Dictionary] rather than a resource per pool because the importer writes scenes
## as TEXT: this serialises to a literal it can emit and re-read, where a sub-resource per
## pool would need ids minted and tracked for a value type that has no identity.
##
## The ids in `grants` name ABILITIES, whatever unlocks each one — dominion through the
## sanction grid, free, or bought at a structure. A pool cannot tell them apart because it does
## not care: see [AbilityCatalog] for what an ability IS.
@export var groups: Array[Dictionary] = []

## Pool capacity when a group leaves it unsaid — one charge, i.e. a plain cooldown.
const DEFAULT_MAX_CHARGES: int = 1

## Per-pool live state, index-aligned with `groups`.
var _charges: Array[int] = []
## TICKS REMAINING on each pool's cooldown, as a FLOAT. Cooldowns are authored in whole
## ticks, but an upgraded pool spends more than one tick's worth of them per tick (see
## _recharge_rate), and rounding that back to an int every frame would quantise an 8% bonus
## to nothing.
var _timers: Array[float] = []
## ability id -> index into `groups`. Built once; an ability in no pool is not granted.
var _pool_of: Dictionary = {}
## Pool index -> the nodes holding that pool's recharge (see hold_recharge). Untyped entries:
## a holder may be freed, which is exactly what releases it.
var _holders: Dictionary = {}


func _ready() -> void:
	_rebuild()


## (Re)derive the live state from `groups`. Public so a test — or a future upgrade that
## edits pools at runtime — can apply a change without reloading the scene.
##
## A pool that starts below capacity starts its cooldown immediately, so `initial_charges:
## 0` reads as "available one cooldown from now" rather than "never, until something spends
## a charge it does not have".
func _rebuild() -> void:
	_charges.clear()
	_timers.clear()
	_pool_of.clear()
	for i: int in groups.size():
		var pool: Dictionary = groups[i]
		_charges.append(_initial_charges(pool))
		_timers.append(float(_cooldown_ticks(pool)))
		for id: Variant in pool.get("grants", []):
			_pool_of[StringName(id)] = i


func _physics_process(_a_delta: float) -> void:
	for i: int in _charges.size():
		var pool: Dictionary = groups[i]
		if _charges[i] >= _max_charges(pool) or _is_held(i):
			continue
		_timers[i] -= _recharge_rate(i)
		if _timers[i] <= 0.0:
			_charges[i] += 1
			_timers[i] = float(_cooldown_ticks(pool))


## Cooldown ticks pool `a_index` spends per physics tick: 1.0, raised by every owned upgrade
## speeding the recharge of an ability the pool grants (UpgradeCatalog.COOLDOWN_RATE_FACTOR).
## Asked each tick rather than stored, so research or a capture takes effect at once.
func _recharge_rate(a_index: int) -> float:
	var host := get_parent() as Entity
	if host == null:
		return 1.0
	var rate: float = 1.0
	for id: Variant in groups[a_index].get("grants", []):
		rate *= UpgradeCatalog.factor_for(
			host, UpgradeCatalog.COOLDOWN_RATE_FACTOR, StringName(str(id))
		)
	return rate


#region Held recharge
## Stop the pool `a_ability_id` draws on from recharging while `a_holder` is in play — what
## that ability PUT into the world holds its charge hostage (a Sapper's planted explosive). The
## hold lifts by itself when the holder is freed, or when `release_recharge` names it: a
## holder that is not a Node (a Spot order, which holds its spotter's charge until it ends)
## outlives its use and has to say so.
func hold_recharge(a_ability_id: StringName, a_holder: Object) -> void:
	var index: int = int(_pool_of.get(a_ability_id, -1))
	if index < 0 or a_holder == null:
		return
	var holders: Array = _holders.get(index, [])
	holders.append(a_holder)
	_holders[index] = holders


## Lift `a_holder`'s hold on the pool `a_ability_id` draws on. The pool's cooldown runs from
## here, as it stood when the hold began.
func release_recharge(a_ability_id: StringName, a_holder: Object) -> void:
	var index: int = int(_pool_of.get(a_ability_id, -1))
	if not _holders.has(index):
		return
	var holders: Array = (_holders[index] as Array).filter(
		func(holder: Variant) -> bool: return not is_same(holder, a_holder)
	)
	if holders.is_empty():
		_holders.erase(index)
	else:
		_holders[index] = holders


## Whether pool `a_index` has a live holder, dropping any that have left play.
func _is_held(a_index: int) -> bool:
	if not _holders.has(a_index):
		return false
	var live: Array = (_holders[a_index] as Array).filter(
		func(holder: Variant) -> bool:
			return (
				is_instance_valid(holder)
				and not (holder is Node and (holder as Node).is_queued_for_deletion())
			)
	)
	if live.is_empty():
		_holders.erase(a_index)
		return false
	_holders[a_index] = live
	return true


## Whether the pool `a_ability_id` draws on is held (see hold_recharge).
func is_recharge_held(a_ability_id: StringName) -> bool:
	var index: int = int(_pool_of.get(a_ability_id, -1))
	return index >= 0 and _is_held(index)


#endregion

#region Positional support
## The ability that identifies a piece as one whose garrison lends a per-completion cooldown
## reduction to the buildings AROUND it — the Colonials' Work Detail, carried by the
## Compound. See Garrison._emit_positional_bonus, the event this marks a host for.
##
## Named here rather than authored as a doc key because exactly one ability does this, and
## a key on every ability doc for a mechanic one of them uses is a schema paying for a case
## that does not exist. It becomes `support:` on the ability the day a second faction wants
## its own version, exactly as Spot's reach will become a doc key the day a second spotter
## does — see gdd/factions/colonial/abilities/spot.md.
const SUPPORT_ABILITY: StringName = &"work_detail"


## Reduce every pool's cooldown by `a_fraction` of its own FULL duration — a one-time
## event, not a rate. A pool already at full charge is untouched: nothing is banked for a
## later completion (see Garrison._emit_positional_bonus). Loops rather than a single
## decrement so a fraction large enough to clear more than one boundary still lands
## correctly, though every authored fraction today is well under that.
func reduce_all_cooldowns(a_fraction: float) -> void:
	for i: int in _charges.size():
		var pool: Dictionary = groups[i]
		if _charges[i] >= _max_charges(pool):
			continue
		_timers[i] -= a_fraction * float(_cooldown_ticks(pool))
		while _timers[i] <= 0.0 and _charges[i] < _max_charges(pool):
			_charges[i] += 1
			_timers[i] += float(_cooldown_ticks(pool))


#endregion


#region Pool fields
## The three authored numbers, each read through one accessor so a missing or nonsensical
## value degrades the same way everywhere. The importer validates them; these clamps are
## what keeps a hand-edited scene from producing a pool that can never recharge.
static func _max_charges(pool: Dictionary) -> int:
	return maxi(1, int(pool.get("max_charges", DEFAULT_MAX_CHARGES)))


static func _initial_charges(pool: Dictionary) -> int:
	var cap: int = _max_charges(pool)
	return clampi(int(pool.get("initial_charges", cap)), 0, cap)


static func _cooldown_ticks(pool: Dictionary) -> int:
	return maxi(1, int(pool.get("cooldown_ticks", 1)))


#endregion

#region Retuning
## The authored doc keys a pool is retuned by, and the pool entry each one is stored as.
const POOL_KEYS: Dictionary = {
	"max_charges": "max_charges", "initial_charges": "initial_charges", "cooldown": "cooldown_ticks"
}


## One pool's authored value by doc key (`cooldown` in ticks), as the pool resolves it.
func pool_value(a_index: int, a_key: String) -> int:
	if a_index < 0 or a_index >= groups.size():
		return 0
	var pool: Dictionary = groups[a_index]
	match a_key:
		"max_charges":
			return _max_charges(pool)
		"initial_charges":
			return _initial_charges(pool)
		"cooldown":
			return _cooldown_ticks(pool)
	return 0


## Change one pool's authored value in play, without the reset _rebuild would make: the pool
## keeps the FRACTION of its charges and of its cooldown it had (debug-tuning.md §An edit is to
## the piece TYPE). Before _ready there is no live state, and _rebuild reads the new value.
func retune_pool(a_index: int, a_key: String, a_value: int) -> void:
	if a_index < 0 or a_index >= groups.size() or not POOL_KEYS.has(a_key):
		return
	var pool: Dictionary = groups[a_index].duplicate()
	var old_max: int = _max_charges(pool)
	var old_cooldown: int = _cooldown_ticks(pool)
	pool[POOL_KEYS[a_key]] = a_value
	groups[a_index] = pool
	if _charges.size() != groups.size():
		return
	_charges[a_index] = clampi(
		roundi(float(_charges[a_index]) * _max_charges(pool) / old_max), 0, _max_charges(pool)
	)
	_timers[a_index] = _timers[a_index] * _cooldown_ticks(pool) / old_cooldown


#endregion


#region Queries
## Whether this piece can use `a_ability_id` at all — before asking whether it is charged.
func grants(a_ability_id: StringName) -> bool:
	return _pool_of.has(a_ability_id)


## Every ability id this piece can use, across all its pools.
func granted_abilities() -> Array[StringName]:
	var out: Array[StringName] = []
	out.assign(_pool_of.keys())
	return out


## Whether this piece can use ANY of its abilities right now, before charges are consulted.
##
## THE ONE THING THAT CAN SWITCH A WHOLE POOL OFF: a structure whose commander is
## infrastructure-strained is unpowered, and an unpowered building's abilities — passive and
## active alike — do nothing until the shortfall is closed. Separate from `is_ready` because
## the two failures have different remedies and the HUD says so (Blocker.UNPOWERED against
## Blocker.RECHARGING): one needs a power plant, the other needs only time.
##
## A pool on something with no host (a bare component in a test) is always operational.
func is_operational() -> bool:
	var host := get_parent() as Commandable
	return host == null or not host.is_unpowered()


## Whether a charge is available for it right now.
func is_ready(a_ability_id: StringName) -> bool:
	var index: int = int(_pool_of.get(a_ability_id, -1))
	return index >= 0 and _charges[index] > 0 and is_operational()


## Charges left in the pool `a_ability_id` draws on, and the pool's capacity. Both 0 for an
## ability this piece does not have, so a HUD readout degrades to "none" rather than lying.
func charges_of(a_ability_id: StringName) -> int:
	var index: int = int(_pool_of.get(a_ability_id, -1))
	return _charges[index] if index >= 0 else 0


func max_charges_of(a_ability_id: StringName) -> int:
	var index: int = int(_pool_of.get(a_ability_id, -1))
	return _max_charges(groups[index]) if index >= 0 else 0


## Physics ticks until the pool's next charge, or 0 when it is already at capacity.
##
## Physics ticks of wall clock, so an upgraded pool counts down at its faster rate. Rounded UP
## so a pool a fraction of a tick from its charge still reads as 1 rather than as ready.
func recharge_remaining(a_ability_id: StringName) -> int:
	var index: int = int(_pool_of.get(a_ability_id, -1))
	if index < 0 or _charges[index] >= max_charges_of(a_ability_id):
		return 0
	return ceili(_timers[index] / _recharge_rate(index))


## How many pools this piece has. The per-POOL queries below are what a readout of the pools
## themselves draws from (CommandableCard's charge dials); the per-ability ones above are what
## a button for one ability asks.
func pool_count() -> int:
	return _charges.size()


func pool_charges(a_index: int) -> int:
	return _charges[a_index] if a_index >= 0 and a_index < _charges.size() else 0


func pool_max_charges(a_index: int) -> int:
	return _max_charges(groups[a_index]) if a_index >= 0 and a_index < groups.size() else 0


## How far pool `a_index` is toward its NEXT charge, 0.0–1.0; 0.0 for a full pool, which has
## no next charge to be working toward.
func pool_recharge_fraction(a_index: int) -> float:
	if a_index < 0 or a_index >= _charges.size() or _charges[a_index] >= pool_max_charges(a_index):
		return 0.0
	var cooldown: float = float(_cooldown_ticks(groups[a_index]))
	return clampf(1.0 - _timers[a_index] / cooldown, 0.0, 1.0)


#endregion


## Spend one charge from the pool `a_ability_id` draws on. Returns false — spending
## nothing — when it has none, so a caller cannot half-fire an ability.
##
## Every ability sharing that pool goes down with it. That IS the mechanic: the pool is the
## resource, and which of its abilities spent the charge does not matter to the others.
func spend(a_ability_id: StringName) -> bool:
	var index: int = int(_pool_of.get(a_ability_id, -1))
	if index < 0 or _charges[index] <= 0 or not is_operational():
		return false
	_charges[index] -= 1
	# Start the clock from the moment it drops below capacity; a pool already recharging
	# keeps its running timer rather than restarting it, so spending a second charge does
	# not push the first one further away.
	if _charges[index] == max_charges_of(a_ability_id) - 1:
		_timers[index] = float(_cooldown_ticks(groups[index]))
	return true
