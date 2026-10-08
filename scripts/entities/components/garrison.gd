class_name Garrison
extends Node

## Garrison component — allows a Actor to hold units inside it.
##
## Garrisoned units are removed from the active scene tree (so they don't
## participate in physics, rendering, AI, or fog-of-war) but kept alive via
## the _garrisoned array reference.  On evacuation they are re-inserted under
## their original Commander node and dispersed to nearby open cells.
##
## WHO may occupy is three bitmasks (frame / armour / movement) plus an optional
## [member occupiable_ids] allowlist; HOW MUCH of the host each occupant consumes is the
## occupant's own [member Entity.occupancy_size] against `capacity`. The two questions are
## deliberately separate, and so are the methods that ask them:
##   admits(unit)        — do the masks and the allowlist let it in?  (a rules question)
##   has_room_for(unit)  — does its occupancy_size still fit? (a capacity question)
##   accepts(unit)       — both, i.e. "can this unit garrison right now"
## A garrison with all three masks CLEARED admits nobody: it is a closed hold that
## can only be filled by a mechanic that puts units in directly (capture, deposit,
## a scenario event) rather than by an Occupy order — see is_closed().
##
## A garrison naming a positive [member sentence_length] is a PRISON: a carrier may deposit
## its captives into it, and they serve that many seconds each, ONE AT A TIME — the captive
## serving is held as itself and pays dominion per cycle, the rest wait their turn unpaid —
## before being CONSUMED. See can_intern(), deposit_from(), paying_count() and
## gdd/systems/combat/colonial-dominion.md §A captive serves a sentence.

#region Occupancy filters
## Which frames / armours / locomotion styles may voluntarily occupy this garrison,
## as bitmasks over Defense.FrameType, Defense.ArmourType and Movement.Mode.
##
## The bit for an enum value is looked up in the maps below rather than computed as
## `1 << value`, because Movement.Mode is NOT a dense enum (GROUNDED = 0x0,
## HOVERING = 0x10, FLYING = 0x11) — shifting by those values would run off the mask.
## Keep the constants, the maps, and the @export_flags hint strings in step.
const FRAME_BIO: int = 1 << 0
const FRAME_MECH: int = 1 << 1
const FRAME_ANY: int = FRAME_BIO | FRAME_MECH

const ARMOUR_LIGHT: int = 1 << 0
const ARMOUR_MEDIUM: int = 1 << 1
const ARMOUR_STRONG: int = 1 << 2
const ARMOUR_ANY: int = ARMOUR_LIGHT | ARMOUR_MEDIUM | ARMOUR_STRONG

const MOVEMENT_GROUNDED: int = 1 << 0
const MOVEMENT_HOVERING: int = 1 << 1
const MOVEMENT_FLYING: int = 1 << 2
const MOVEMENT_AERIAL: int = MOVEMENT_HOVERING | MOVEMENT_FLYING
const MOVEMENT_ANY: int = MOVEMENT_GROUNDED | MOVEMENT_AERIAL

const FRAME_BITS: Dictionary = {
	Defense.FrameType.BIO: FRAME_BIO,
	Defense.FrameType.MECH: FRAME_MECH,
}
const ARMOUR_BITS: Dictionary = {
	Defense.ArmourType.LIGHT: ARMOUR_LIGHT,
	Defense.ArmourType.MEDIUM: ARMOUR_MEDIUM,
	Defense.ArmourType.STRONG: ARMOUR_STRONG,
}
const MOVEMENT_BITS: Dictionary = {
	Movement.Mode.GROUNDED: MOVEMENT_GROUNDED,
	Movement.Mode.HOVERING: MOVEMENT_HOVERING,
	Movement.Mode.FLYING: MOVEMENT_FLYING,
}

## Frames (Defense.frame_type) this garrison accepts. Both by default — a shelter
## doesn't care what its occupants are made of. Clear a bit for a hold only flesh
## (or only machines) can enter.
@export_flags("Bio:1", "Mech:2") var occupiable_frames: int = FRAME_ANY

## Armour classes (Defense.armour_type) this garrison accepts. All by default; narrow
## it for a host that only fits infantry-weight occupants.
@export_flags("Light:1", "Medium:2", "Strong:4") var occupiable_armours: int = ARMOUR_ANY

## Locomotion styles (Movement.mode) this garrison accepts. GROUNDED only by default,
## which is the reach every existing garrison was written against (Occupy used to hard-
## code that check). Add Hovering / Flying for a host that can take aircraft — e.g. a
## hangar or a carrier.
@export_flags("Grounded:1", "Hovering:2", "Flying:4")
var occupiable_movements: int = MOVEMENT_GROUNDED

## Piece ids ([member Entity.id]) this garrison accepts, as an ALLOWLIST checked on top
## of the three masks. EMPTY — the default — means no identity restriction at all, and
## the masks decide alone.
##
## Empty means "everything" here and "nobody" on the masks, and the asymmetry is
## deliberate: a mask enumerates a closed enum, so naming every member is a statement a
## host can actually make, while piece ids are open-ended and no host could list them
## all. A hold for one named piece has no other way to say so — the Compound admits
## Servants and nothing else, and a Servant's frame, armour and locomotion are shared
## with every other light soldier the faction fields.
@export var occupiable_ids: Array[StringName] = []
#endregion

#region Properties
## Total occupancy this garrison holds, measured in occupancy_size — NOT a head
## count. Four size-1 infantry fill a capacity of 4; two size-2 collectives fill
## the same host.
@export var capacity: int = 4
## When true, garrisoned units can fire their weapons from inside this garrison.
## The garrison owner's position and aggro volumes are used; garrisoned units supply
## the weapons. Set false for purely protective garrisons that offer no fire support.
@export var bunker: bool = true
## When true, garrisoned units are evacuated (returned to the scene) when the host
## dies. When false they die with the host. Defaults to true so garrisons are a
## safe haven rather than a death trap.
@export var preserve_occupants: bool = true
## Extra attack range (world units) granted to occupants firing out of this
## garrison, on top of each weapon's own range. Authored as the gap between two reach
## buckets, so it tracks the library. Only meaningful when `bunker` is true.
@export var range_bonus: float = 0.0
## The reach (world units) one occupant PIECE fires out of this garrison with, keyed by
## [member Entity.id] — SET, in place of its weapon's own reach plus [member range_bonus],
## and never below that weapon's own reach. The first per-occupant property: a host whose
## character depends on WHICH unit holds it (the Warden's Security Tower, where a garrisoned
## Shock Drone fires at long range) says so here. See
## gdd/design-framework/static-defence.md §Libertarians.
@export var reach_by_piece: Dictionary[StringName, float] = {}

## Whether this hold TAKES PRISONERS by contact — the Colonial Stock Truck's cage, and nothing
## else. Capturing is a unique property of that unit (Alex, 2026-10-07): a transport's hold
## admits light infantry by order and never by running them over, so without this flag the
## Sloop, whose hold has room and takes LIGHT BIO occupants, captured the soldiers it crushed.
## Doc key `captures:`; false by default, so a hold has to say so.
@export var captures: bool = false

## Whether occupants may be ordered out (see can_release). Defaults to true: a garrison you
## can walk into is one you can walk out of, and even a hold filled by capture releases what
## it holds — an occupant nothing can ever let out is a cell, and wants saying explicitly.
@export var releasable: bool = true

## Seconds a carrier takes per captive when it DEPOSITS its load: the first goes over when the
## deposit interaction completes, each next one this long after. Zero hands the whole load over
## at once. Set on the carrier, so more trucks unload faster (gdd/tasks.md T-044 tunes it).
@export var unload_time: float = 0.0

## Seconds a captive DEPOSITED here serves before being consumed. Setting it positive is
## what makes a garrison a prison in the deposit sense (see can_intern): a carrier may hand
## its captives over, and each one, when its turn comes, pays dominion per cycle for this long
## before this garrison frees it (SENTENCES_AT_ONCE). Zero (the default) means the host takes
## no deposits at all and sentences nobody; an occupant of such a garrison simply stays until
## evacuated, like any other.
##
## Calibrated 2026-10-05 against the Technocratic Lab route — see
## gdd/systems/macroeconomics/pacing/dominion-rate-analysis.md §One-at-a-time processing and
## gdd/systems/combat/colonial-dominion.md §A captive serves a sentence.
@export var sentence_length: float = 0.0

## How many captives a prison sentences at once. ONE: the rest of its places hold captives
## waiting their turn, paying nothing and with their terms not yet started. A const rather
## than a doc key because no piece wants another value; it is named so the throughput
## projection (Commander.projected_dominion_rate) reads the same number this file obeys.
const SENTENCES_AT_ONCE: int = 1

## Seconds remaining on each tracked occupant's sentence, keyed by unit, in arrival order.
## Only occupants of a garrison with sentence_length > 0 are tracked at all — see garrison().
## The first SENTENCES_AT_ONCE keys are the ones serving; insertion order is the queue, which
## is why nothing may rebuild this Dictionary out of order.
var _sentence_remaining: Dictionary = {}

## Units currently garrisoned.  Held as orphaned nodes — removed from the
## scene tree but not freed.
var _garrisoned: Array[Actor] = []

## Units that have registered intent to garrison this shelter while it lands.
## Each entry auto-removes itself via tree_exiting when the unit dies.
var _pending_garrison_units: Array[Actor] = []

## When a commanderless (neutral) garrison is garrisoned, it temporarily adopts
## the garrisoning units' commander. `_adopted_commander` records that this
## happened so we can revert on full evacuation; `_restore_commander` holds the
## original (neutral) commander to revert to. A garrison that already had a real
## commander never adopts, so it is left untouched on evacuation.
var _adopted_commander: bool = false
var _restore_commander: Commander = null
#endregion


#region Occupancy
## How much of `capacity` `unit` consumes. Clamped to at least 1 so a mis-authored
## size of 0 can't let an unbounded number of units in.
static func size_of(unit: Actor) -> int:
	return maxi(1, unit.occupancy_size) if unit != null else 1


## Occupancy currently held, summed over the occupants' sizes.
func occupied_size() -> int:
	var total: int = 0
	for unit: Actor in _garrisoned:
		total += size_of(unit)
	return total


## Occupancy still free.
func remaining_capacity() -> int:
	return capacity - occupied_size()


## True when the occupancy masks let `unit` in — a rules check only, ignoring how
## full the garrison is. A unit missing the component a mask reads (no Defense, no
## Movement) is NOT admitted: an occupant has to answer every question asked of it.
func admits(a_unit: Actor) -> bool:
	if a_unit == null or not is_instance_valid(a_unit):
		return false
	# An UNFINISHED host takes nobody. A building still going up has no inside to stand in,
	# and letting units enter one would park them somewhere that does not exist yet — the
	# same rule that stops a half-built structure shooting or training. Deliberately here
	# rather than only in Occupy.meets_precondition, so the mechanics that put units in
	# WITHOUT consent (capture, deposit) agree with the ones that ask.
	var host := get_parent() as Actor
	if host != null and not host.is_built:
		return false
	var frame_bit: int = (
		FRAME_BITS.get(a_unit.defense.frame_type, 0) if a_unit.defense != null else 0
	)
	if occupiable_frames & frame_bit == 0:
		return false
	var armour_bit: int = (
		ARMOUR_BITS.get(a_unit.defense.armour_type, 0) if a_unit.defense != null else 0
	)
	if occupiable_armours & armour_bit == 0:
		return false
	var movement_bit: int = (
		MOVEMENT_BITS.get(a_unit.movement.mode, 0) if a_unit.movement != null else 0
	)
	if occupiable_movements & movement_bit == 0:
		return false
	# An empty allowlist restricts nothing — see occupiable_ids.
	if not occupiable_ids.is_empty() and not occupiable_ids.has(a_unit.id):
		return false
	return true


## True when `unit`'s occupancy_size still fits in the remaining capacity — a capacity
## check only, ignoring the masks. This is the check for mechanics that put units in
## WITHOUT their consent (capture, deposit, a scenario event authoring a starting load),
## which are deliberately not subject to the voluntary-occupancy masks.
func has_room_for(a_unit: Actor) -> bool:
	return remaining_capacity() >= size_of(a_unit)


## True when `unit` may garrison right now: the masks admit it AND it fits.
func accepts(a_unit: Actor) -> bool:
	return admits(a_unit) and has_room_for(a_unit)


## True when no unit can ever occupy this garrison voluntarily (every mask cleared).
## A closed garrison is a HOLD — the stock truck's cage — filled only by capture /
## deposit / scenario authoring, and never by an Occupy order.
##
## ENTRY ONLY. Whether occupants may be let out again is `releasable`, asked through
## can_release(): the two directions of the door are separate statements, because the
## Compound takes nobody by order and still lets out the Servants delivered to it.
##
## NOT what marks a deposit target: the Compound admits Servants by order and is still
## where captives are interned. That question is can_intern().
func is_closed() -> bool:
	return occupiable_frames == 0 and occupiable_armours == 0 and occupiable_movements == 0


## True when occupants may be ordered OUT of this garrison — by the Evacuate command, or one
## at a time by clicking an occupant's card in the info panel. Which of them actually leave
## is can_release_occupant: the host's own side, never a captive.
##
## Separate from is_closed(), which is about getting IN: the Compound takes nobody by order
## and still lets out the Servants a Stock Truck delivered.
func can_release() -> bool:
	return releasable


## True when `a_unit`, held here, may be let out by an ORDER — Evacuate, or its info-panel
## card. Only the host's own side leaves that way: a captive leaves when the host dies (back
## to its own side) or is deposited, never because its captor's owner asked. So a Servant
## rides a Stock Truck and walks out of a Compound, and the prisoners beside it stay.
func can_release_occupant(a_unit: Actor) -> bool:
	return can_release() and a_unit in _garrisoned and not is_captive(a_unit)


## True when `a_unit` is held by a side it does not belong to — taken by capture, or
## deposited. A neutral host adopts its occupants' side (see garrison), so its occupants are
## never captives.
func is_captive(a_unit: Actor) -> bool:
	var host := get_parent() as Actor
	return host != null and not a_unit.is_friendly_to(host)


## True when `captor` would take `captive` PRISONER by running it over — the whole rule of
## an abduction, asked from the outside because it is about a pairing rather than about one
## garrison. A capture is a capture-filled hold being filled: no Occupy is issued and the
## occupancy masks are not consulted, which is exactly why the truck's cage is authored
## closed (see is_closed).
##
## Capturable = a non-friendly, non-structure, LIGHT-armoured BIOLOGICAL unit — an enemy
## soldier or one of a Shelter's neutral Terrestrials — when the captor has a hold that
## CAPTURES (`captures`) with room left. NEUTRALS QUALIFY, which is why this asks
## is_friendly_to rather than is_enemy_of.
##
## Room is part of the rule, and a captor that is full simply answers false. It does not
## follow that the contact is harmless: see Actor._run_over_overlapping_units, where a
## refused capture falls straight through to the ordinary crush.
##
## Why it works this way: gdd/systems/combat/garrison-and-transport.md §Capture is a crush.
static func can_capture(captor: Actor, captive: Actor) -> bool:
	if (
		captor == null
		or captive == null
		or not is_instance_valid(captor)
		or not is_instance_valid(captive)
		# Killed earlier this frame: still answering physics queries until the tree flush,
		# and freed inside the cage when it comes (seen 2026-10-07 in self-play).
		or captive.is_queued_for_deletion()
	):
		return false
	var cage: Garrison = captor.get_node_or_null("Garrison") as Garrison
	if cage == null or not cage.captures or not cage.has_room_for(captive):
		return false
	if captive.is_friendly_to(captor) or captive.structure_is_active():
		return false
	if captive.defense == null or captive.defense.armour_type != Defense.ArmourType.LIGHT:
		return false
	return EntityAttribute.evaluate(EntityAttribute.Type.IS_BIOLOGICAL, captive)


## True when this garrison takes deposited captives and has room for one more — the
## precondition for [Interaction] `DEPOSIT`.
##
## A positive `sentence_length` is what marks a prison apart from an ordinary garrison,
## replacing the `is_closed()` test that did the job while the Compound was itself a closed
## hold. Stating it positively is also what stops a safehouse being mistaken for a camp: an
## open garrison no more sentences prisoners than a closed transport does.
##
## Room is asked as one slot of the smallest size rather than the deposited piece's own
## `occupancy_size`, matching every other unconsented entry. Keep captured pieces at size 1.
func can_intern() -> bool:
	return sentence_length > 0.0 and can_garrison()


## Take `source`'s captives directly into this garrison, UNCONVERTED — a captive stays
## itself, off the tree, and starts serving `sentence_length` here exactly as it would have
## served the rest of it in `source` (see garrison()). Returns how many were moved; stops
## early when this garrison fills, leaving the rest with the carrier (a partial deposit), or
## after `a_limit` captives when that is not negative — the carrier unloading one at a time.
##
## Ownership does not change here: a captive's `Ownership` still names the side it was taken
## from, so a Compound destroyed mid-term still hands it back there (evacuate/evacuate_one),
## not to the depositor. See gdd/systems/combat/colonial-dominion.md §A captive serves a
## sentence.
func deposit_from(a_source: Garrison, a_limit: int = -1) -> int:
	if a_source == null or sentence_length <= 0.0:
		return 0
	var moved: int = 0
	for captive: Actor in a_source.occupants().duplicate():
		if moved == a_limit or not has_room_for(captive):
			break
		a_source.detach(captive)
		garrison(captive)
		moved += 1
	return moved


## Whether a deposit from `a_source` would move anything now: it holds a captive and this
## garrison has room for the next one.
func can_take_next_from(a_source: Garrison) -> bool:
	if a_source == null or sentence_length <= 0.0:
		return false
	var next: Array = a_source.occupants()
	return not next.is_empty() and has_room_for(next.front() as Actor)


## Remove `unit` from this garrison and free it WITHOUT returning it to the scene — a
## sentence reaching its end. Its Loadout is put back first: a bunker hoists that onto the
## host (see garrison), and freeing the unit while it is parented elsewhere would leave the
## weapons behind.
func discard(a_unit: Actor) -> void:
	if not (a_unit in _garrisoned):
		return
	a_unit.garrisoned_in = null
	_garrisoned.erase(a_unit)
	_restore_loadout(a_unit)
	# free(), not queue_free(): an occupant is already out of the scene tree, so there is no
	# live node to tear down at a frame boundary — and leaving a consumed captive answering
	# queries for the rest of the frame is exactly what [Liberatable] documents as a trap.
	a_unit.free()
	_refresh_aggro_range()


## Remove `unit` from this garrison WITHOUT freeing it or returning it to the scene — the
## live half of a transfer, where discard() would wrongly destroy an object the caller is
## about to re-home elsewhere (see deposit_from). Loadout is restored first, same as
## discard(), so a bunker's hoisted weapons follow the unit rather than staying behind.
func detach(a_unit: Actor) -> void:
	if not (a_unit in _garrisoned):
		return
	a_unit.garrisoned_in = null
	_garrisoned.erase(a_unit)
	_sentence_remaining.erase(a_unit)
	_restore_loadout(a_unit)
	_refresh_aggro_range()


#endregion

#region Sentences
## What one adjacent structure's ability pools have their cooldown reduced by, on each
## sentence completing here — a percentage of the pool's own FULL cooldown, not of its
## remaining time (see colonial-dominion.md §The positional bonus is an event, not a rate).
## A CONSTANT, as the retired passive per-occupant recharge rate was before it: the number is
## Work Detail's, not any one Compound's.
const SENTENCE_COOLDOWN_BONUS: float = 0.08


func _physics_process(a_delta: float) -> void:
	if _sentence_remaining.is_empty():
		return
	# Only the head of the queue serves (SENTENCES_AT_ONCE); the captives behind it wait with
	# their terms untouched. Snapshot the serving keys: discard() below mutates
	# _sentence_remaining as each completed captive is freed. A term that ends mid-step does
	# not hand its leftover to the next captive — the next one starts on the following tick.
	for unit: Actor in _sentence_remaining.keys().slice(0, SENTENCES_AT_ONCE):
		if not is_instance_valid(unit):
			_sentence_remaining.erase(unit)
			continue
		_sentence_remaining[unit] -= a_delta
		if _sentence_remaining[unit] <= 0.0:
			_sentence_remaining.erase(unit)
			discard(unit)
			_emit_positional_bonus()


## On a sentence completing, reduce the cooldown of every ability pool on every
## edge-adjacent friendly structure by SENTENCE_COOLDOWN_BONUS — Work Detail, carried by
## whichever piece grants it (Abilities.SUPPORT_ABILITY). The three things that switch it
## off are asked of the SUPPORTER (this host, the Compound), same as the passive rate this
## replaces: it must be finished, and its commander's infrastructure must cover its upkeep.
## Nothing beyond friendliness is asked of the structure being helped — matching the
## passive it replaces, which never gated on the beneficiary's own state either.
func _emit_positional_bonus() -> void:
	var host := get_parent() as Actor
	if (
		host == null
		or host.map == null
		or not host.is_built
		or host.is_unpowered()
		or not _grants_positional_bonus(host)
	):
		return
	for neighbor: Entity in SU.edge_adjacent_structures(host.map, host):
		var supported := neighbor as Actor
		if supported == null or not supported.is_friendly_to(host):
			continue
		var pool := supported.get_node_or_null("Abilities") as Abilities
		if pool != null:
			pool.reduce_all_cooldowns(SENTENCE_COOLDOWN_BONUS)


static func _grants_positional_bonus(a_host: Actor) -> bool:
	var pool := a_host.get_node_or_null("Abilities") as Abilities
	return pool != null and pool.grants(Abilities.SUPPORT_ABILITY)


#endregion


#region Public API
## True when at least one more occupant of the smallest possible size (1) can be
## accepted. Prefer accepts()/has_room_for() when a specific unit is in hand — this
## unit-less form is for callers that only ask "does this host have any room left".
func can_garrison() -> bool:
	return remaining_capacity() >= 1


## Register `unit` as intending to garrison once this shelter touches down.
## Idempotent — a second call for the same unit is silently ignored.
## Uses a CONNECT_ONE_SHOT tree_exiting hook so a unit that dies (or otherwise
## leaves the tree) removes itself exactly once, mirroring register_builder().
func register_garrison_intent(a_unit: Actor) -> void:
	if a_unit in _pending_garrison_units:
		return
	_pending_garrison_units.append(a_unit)
	a_unit.tree_exiting.connect(unregister_garrison_intent.bind(a_unit), CONNECT_ONE_SHOT)


## Drop `unit` from the pending list. When the list becomes empty and the host is
## grounded, lift off so it resumes normal HOVERING without an explicit command.
##
## Deliberately does NOT read or disconnect `unit.tree_exiting`. A dying unit reaches
## this both via that ONE_SHOT signal AND via Occupy's PREDELETE teardown, by which
## point the unit is mid-free — and touching a freed node's signal crashes Godot
## entirely. The one-shot connection cleans itself up; a still-live unit that
## unregistered manually just keeps a harmless spent hook (as register_builder does).
func unregister_garrison_intent(a_unit: Actor) -> void:
	_pending_garrison_units.erase(a_unit)
	if _pending_garrison_units.is_empty():
		var owner_cmd := get_parent() as Actor
		if owner_cmd != null and owner_cmd.aerial != null:
			owner_cmd.aerial.take_off()


## Tell all pending units to drop their garrison command, then clear the list.
## Called when the shelter receives a new command while units are waiting.
func cancel_pending_garrison() -> void:
	var pending: Array[Actor] = _pending_garrison_units.duplicate()
	for unit: Actor in pending:
		unregister_garrison_intent(unit)
		if is_instance_valid(unit):
			unit.update_commands(null)


func garrisoned_count() -> int:
	return _garrisoned.size()


## How many occupants are CAPTIVES (is_captive) — what a carrier has to bank, as opposed to
## its own side riding along. A Stock Truck's cage carries Servants by order and prisoners by
## capture, and a Servant is not cargo.
func captive_count() -> int:
	return _garrisoned.filter(is_captive).size()


## The occupants that earn their host per-occupant dominion right now (OccupantDominionGenerator).
## In a prison only the captives SERVING pay — at most SENTENCES_AT_ONCE — and the ones waiting
## their turn do not; in any other garrison every occupant counts.
func paying_count() -> int:
	if sentence_length <= 0.0:
		return garrisoned_count()
	return mini(_sentence_remaining.size(), SENTENCES_AT_ONCE)


## Free all garrisoned units without returning them to the scene.
## Used when preserve_occupants is false and the host is destroyed.
func kill_occupants() -> void:
	for unit: Actor in _garrisoned:
		if is_instance_valid(unit):
			unit.garrisoned_in = null
			unit.queue_free()
	_garrisoned.clear()


## True when this garrison is ACTIVELY holding at least one occupant that carries a
## weapon — the precondition for any bunker fire to project. Merely being able to accept
## such units (an empty or unarmed-only garrison) returns false. Target-agnostic, unlike
## any_garrison_can_target(); used to rank a bunker host as a combat target.
func has_armed_occupants() -> bool:
	for unit: Actor in _garrisoned:
		if unit.weapon_inventory != null and unit.weapon_inventory.has_weapons():
			return true
	return false


## True when at least one garrisoned unit carries a weapon that can target `target`.
func any_garrison_can_target(a_target: Entity) -> bool:
	if not bunker:
		return false
	for unit: Actor in _garrisoned:
		if (
			unit.weapon_inventory != null
			and unit.weapon_inventory.weapon_for_target(a_target) != null
		):
			return true
	return false


## Fire every garrisoned unit's first target-capable weapon at `target` from
## `owner`'s world position, for those weapons that are loaded and in range.
## Each weapon advances its own reload timer in Weapon._physics_process because
## its Loadout was reparented onto `owner` at garrison time (see garrison()), so
## firing simply respects Weapon.is_ready() rather than tracking timers here.
func tick_bunker_fire(a_owner: Actor, a_target: Entity) -> void:
	if not bunker:
		return
	for unit: Actor in _garrisoned:
		var weapon := _firing_weapon(unit, a_owner, a_target)
		if weapon != null:
			weapon.fire(a_owner, a_target)


## True when at least one garrisoned unit carries a weapon that can target, is
## loaded, and reaches `target` from `owner`'s position — i.e. a bunker volley
## would actually produce a projectile this tick.
func can_fire_at(a_owner: Actor, a_target: Entity) -> bool:
	if not bunker:
		return false
	for unit: Actor in _garrisoned:
		if _firing_weapon(unit, a_owner, a_target) != null:
			return true
	return false


## True when at least one garrisoned unit carries a weapon that can target `target` and
## reaches it from `owner`'s position, loaded or not — whether a bunker could EVER fire on
## it from where it stands, rather than whether it can this tick (can_fire_at).
func can_reach(a_owner: Actor, a_target: Entity) -> bool:
	if not bunker:
		return false
	return _garrisoned.any(
		func(unit: Actor) -> bool: return _reaching_weapon(unit, a_owner, a_target) != null
	)


## The first weapon in `unit`'s inventory that can target `target`, is ready to
## fire, and reaches it from `owner`'s position; null if none qualifies.
func _firing_weapon(a_unit: Actor, a_owner: Actor, a_target: Entity) -> Weapon:
	var weapon := _reaching_weapon(a_unit, a_owner, a_target)
	return weapon if weapon != null and weapon.is_ready() else null


## The first weapon in `unit`'s inventory that can target `target` and reaches it from
## `owner`'s position, loaded or not; null if none does.
func _reaching_weapon(a_unit: Actor, a_owner: Actor, a_target: Entity) -> Weapon:
	if a_unit.weapon_inventory == null:
		return null
	var weapon := a_unit.weapon_inventory.weapon_for_target(a_target)
	if weapon == null:
		return null
	var bonus: float = reach_bonus_for(a_unit, weapon.reach_for(a_target))
	if not SU.is_in_attack_range(weapon, a_owner, a_target, bonus):
		return null
	return weapon


## Remove `unit` from the active scene tree and store it here.
func garrison(a_unit: Actor) -> void:
	_adopt_commander_if_neutral(a_unit)
	# For a bunker, hoist the unit's weapon inventory onto this garrison's owner
	# so its weapons keep advancing their _physics_process reload timers — an
	# orphaned (off-tree) unit doesn't tick, so otherwise its weapons would never
	# reload or fire. The unit itself still leaves the tree; only its Loadout
	# stays, reparented under the owner.
	var owner_node := get_parent()
	if bunker and owner_node != null and a_unit.weapon_inventory != null:
		a_unit.weapon_inventory.reparent(owner_node, false)
	# Already-orphaned units reach here too (a captive handed straight into a hold),
	# so the detach is conditional rather than assuming a parent.
	var unit_parent: Node = a_unit.get_parent()
	if unit_parent != null:
		unit_parent.remove_child(a_unit)
	# CLEAR THE SELECTION STATE ON THE WAY IN, the mirror of what evacuate_one does on the way
	# out. A unit ordered into a transport is usually selected at the moment it boards, and
	# leaving the flag set is stale state on something that is no longer in the world.
	#
	# It is also load-bearing rather than tidiness: `Selectable.select()` returns whether the
	# state CHANGED, and every selection path treats false as "this cannot be selected". So an
	# occupant that kept a stale SELECTED flag could never be picked again — which is exactly
	# what stopped its info-panel card selecting it.
	if a_unit.selectable != null:
		a_unit.selectable.deselect()
	a_unit.garrisoned_in = self
	_garrisoned.append(a_unit)
	if sentence_length > 0.0:
		_sentence_remaining[a_unit] = sentence_length
	_refresh_aggro_range()


## When this garrison has no commander (neutral, id 0), adopt the garrisoning
## unit's commander so the structure reads as that team's while occupied. The
## original (neutral) commander is remembered so evacuation can revert it. Only
## the first garrisoning unit triggers the adoption; subsequent units share the
## same commander (enforced by the Occupy precondition), so this is a no-op
## for them. A garrison that already had a real commander is never touched.
func _adopt_commander_if_neutral(a_unit: Actor) -> void:
	if _adopted_commander:
		return
	var owner_cmd := get_parent() as Actor
	if owner_cmd == null or owner_cmd.commander_id != 0:
		return
	# A unit that never entered the tree has no resolved Ownership to read a commander
	# from (see Entity.ownership), so there is nothing to adopt.
	if a_unit.ownership == null or a_unit.commander == null:
		return
	_restore_commander = owner_cmd.commander
	_adopted_commander = true
	owner_cmd.commander = a_unit.commander


## Restore all garrisoned units to the scene tree.
## Routes to the appropriate placement strategy depending on whether the
## garrison owner occupies the terrain grid (has an Structure component) or
## is itself a non-grid entity such as a unit.
func evacuate(a_map: Map) -> void:
	var owner_cmd := get_parent() as Actor

	if owner_cmd != null and owner_cmd.structure_is_active():
		_evacuate_from_structure(owner_cmd, a_map)
	else:
		_evacuate_from_unit(owner_cmd, a_map)

	for unit: Actor in _garrisoned:
		if is_instance_valid(unit):
			unit.garrisoned_in = null
	_garrisoned.clear()
	_sentence_remaining.clear()
	_revert_adopted_commander(owner_cmd)
	_refresh_aggro_range()

	# If the host landed to accept garrison units, return it to hover altitude.
	if (
		owner_cmd != null
		and owner_cmd.aerial != null
		and owner_cmd.aerial.mode == Movement.Mode.HOVERING
	):
		owner_cmd.aerial.take_off()


## Turn out every occupant an order may release (can_release_occupant), keeping the rest —
## a captive stays, and so does the rest of its sentence. What Evacuate does; evacuate() is
## for the host's death, where everyone leaves.
func evacuate_by_order(a_map: Map) -> void:
	if not can_release():
		return
	var kept: Array[Actor] = []
	kept.assign(
		_garrisoned.filter(
			func(a_unit: Actor) -> bool: return not can_release_occupant(a_unit)
		)
	)
	if kept.is_empty():
		evacuate(a_map)
		return
	var kept_sentences: Dictionary = {}
	for unit: Actor in kept:
		if _sentence_remaining.has(unit):
			kept_sentences[unit] = _sentence_remaining[unit]
	# evacuate() turns out whatever _garrisoned holds, so it is handed only the released and
	# the kept are put back after: one placement pass, spreading the released together.
	_garrisoned.assign(
		_garrisoned.filter(func(a_unit: Actor) -> bool: return not (a_unit in kept))
	)
	evacuate(a_map)
	_garrisoned = kept
	_sentence_remaining = kept_sentences
	_refresh_aggro_range()


## Evacuate a SINGLE occupant `unit` (used by the info panel's per-occupant evacuate),
## returning just that unit to the scene next to the host and dispersing it. Mirrors the
## per-unit placement/command logic of evacuate() but for one occupant. The adopted
## commander is only reverted once the garrison empties. No-op when `unit` isn't held here.
func evacuate_one(a_unit: Actor, a_map: Map) -> void:
	if not (a_unit in _garrisoned):
		return
	var owner_cmd := get_parent() as Actor

	# Seed placement from a passable cell next to a structure host's footprint (its own
	# cells are off-navmesh), otherwise from the host's own position (a unit host).
	var center: Vector2
	if owner_cmd != null and owner_cmd.structure_is_active() and a_map != null:
		var cells: Array[Vector2i] = SU.passable_cells_adjacent_to(owner_cmd, a_map)
		center = (
			VU.in_xz(a_map.grid_to_world(cells[0]))
			if not cells.is_empty()
			else VU.in_xz(owner_cmd.global_position)
		)
	else:
		center = VU.in_xz(owner_cmd.global_position) if owner_cmd != null else Vector2.ZERO

	var radii: Array[float] = [a_unit.bounding_radius(CollisionLayers.Mask.MOVEMENT_OBSTRUCTION)]
	var world: World3D = (
		owner_cmd.get_world_3d()
		if owner_cmd != null
		else (a_map.get_world_3d() if a_map != null else null)
	)
	var spawn_xz: Vector2 = _spread_points(a_map, center, radii, world, 1)[0]
	var height_offset: float = a_unit.height_offset()
	var y: float = (
		a_map.terrain_height_at(spawn_xz) + height_offset
		if a_map != null
		else (owner_cmd.global_position.y if owner_cmd != null else 0.0)
	)
	var spawn_pos := Vector3(spawn_xz.x, y, spawn_xz.y)

	a_unit.garrisoned_in = null
	_garrisoned.erase(a_unit)
	_sentence_remaining.erase(a_unit)
	if not _return_to_commander(a_unit):
		return
	_restore_loadout(a_unit)
	a_unit.global_position = spawn_pos
	# Return the evacuee UNSELECTED: the player evacuated it from the info panel while
	# the garrison host is the selected unit, so releasing it must not steal the
	# selection (or leave a stale selection ring carried over from before it garrisoned).
	# The controller keeps the host in its selection set; we just make sure the released
	# unit doesn't come back looking selected.
	if a_unit.selectable != null:
		a_unit.selectable.deselect()
	if a_map != null:
		a_unit.update_commands(_release_commands(a_unit, owner_cmd, a_map, spawn_pos))

	if _garrisoned.is_empty():
		_revert_adopted_commander(owner_cmd)
	_refresh_aggro_range()
	if (
		_garrisoned.is_empty()
		and owner_cmd != null
		and owner_cmd.aerial != null
		and owner_cmd.aerial.mode == Movement.Mode.HOVERING
	):
		owner_cmd.aerial.take_off()


## The units currently garrisoned (read-only view for UI such as the info panel's
## per-occupant cards). Callers must not mutate the returned array.
func occupants() -> Array[Actor]:
	return _garrisoned


## Revert a commander adopted from garrisoning units once everyone has left, so
## the garrison returns to neutral. No-op when the garrison had its own commander
## to begin with (it was never adopted), so a preexisting commander is preserved.
func _revert_adopted_commander(a_owner_cmd: Actor) -> void:
	if not _adopted_commander:
		return
	if a_owner_cmd != null:
		a_owner_cmd.commander = _restore_commander
	_adopted_commander = false
	_restore_commander = null


#endregion


#region Private helpers
## Re-parent a released occupant under its own Commander and report whether that
## worked. It usually does; the exception is an occupant with nobody to go back to —
## a unit whose commander has been freed, or a captive that was handed into a hold
## without ever entering the tree (so its Ownership never resolved). Those are FREED
## rather than leaked as orphans, mirroring what the old Inventory eject did.
##
## Matters most for the release-on-death path: a garrison holding PRISONERS returns
## each one to ITS OWN commander, not the host's — that is exactly how a destroyed
## stock truck / Compound frees the units it was holding.
func _return_to_commander(a_unit: Actor) -> bool:
	var cmd: Commander = a_unit.commander if a_unit.ownership != null else null
	if cmd == null or not is_instance_valid(cmd):
		a_unit.free()
		return false
	cmd.add_child(a_unit)
	return true


## Move a garrisoned unit's weapon inventory back under the unit, reversing the
## hoist done in garrison(). Call after the unit has been re-added to the tree.
## A no-op when the Loadout was never moved (non-bunker garrison, or unit had no
## inventory), detected via the Loadout's current parent.
func _restore_loadout(a_unit: Actor) -> void:
	var loadout := a_unit.weapon_inventory
	if loadout != null and loadout.get_parent() != a_unit:
		loadout.reparent(a_unit, false)


## Evacuation path for garrison owners that occupy the terrain grid (structures).
## Units are spread around the footprint via _spread_points — same navmesh-
## snapped, non-overlapping placement _evacuate_from_unit uses — so a full
## garrison evacuating on one frame doesn't stack its units on top of each other.
func _evacuate_from_structure(a_owner_cmd: Actor, a_map: Map) -> void:
	var count := _garrisoned.size()
	if count == 0:
		return

	# The structure's own centroid usually isn't on the navmesh (building cells
	# are excluded from it), so _spread_points can't anchor there directly — seed
	# from a passable cell adjacent to the footprint. When the host has a rally
	# destination the evacuees are sent to (see _release_commands), seed from the
	# adjacent cell CLOSEST to it so they emerge on that side — mirroring the rally
	# bias Production._spawn_unit applies to freshly-trained units. With no rally,
	# any adjacent cell (shuffled) will do.
	## Every cell lookup here needs a map; with none, anchor on the host itself and let the
	## ring fallback in _spread_points do the placing (see the height fallback below).
	var rally: MoveCommand = a_owner_cmd.rally_destination() if a_map != null else null
	var seed_cell: Vector2i = (
		SU.nearest_footprint_adjacent_cell(rally.message.position, a_owner_cmd, a_map)
		if rally != null
		else Vector2i(-1, -1)
	)
	var center: Vector2 = VU.in_xz(a_owner_cmd.global_position)
	if a_map != null:
		if seed_cell != Vector2i(-1, -1):
			center = VU.in_xz(a_map.grid_to_world(seed_cell))
		else:
			var seed_cells := SU.passable_cells_adjacent_to(a_owner_cmd, a_map)
			if not seed_cells.is_empty():
				center = VU.in_xz(a_map.grid_to_world(seed_cells[0]))
	# Each evacuee is spaced by its OWN body radius (see _evacuee_radii), so a mix
	# of large and small occupants packs tightly rather than by one shared radius.
	var points: Array[Vector2] = _spread_points(
		a_map, center, _evacuee_radii(), a_owner_cmd.get_world_3d(), count
	)

	for i in range(count):
		var unit: Actor = _garrisoned[i]
		var spawn_xz: Vector2 = points[i]
		var height_offset: float = unit.height_offset()
		# Fall back to the host's own altitude with no map to sample, mirroring
		# _evacuate_from_unit — releasing the occupants matters more than placing them well,
		# so a map-less evacuation must not fault before anyone gets out.
		var y: float = (
			a_map.terrain_height_at(spawn_xz) + height_offset
			if a_map != null
			else a_owner_cmd.global_position.y
		)
		var spawn_pos := Vector3(spawn_xz.x, y, spawn_xz.y)

		if not _return_to_commander(unit):
			continue
		_restore_loadout(unit)
		unit.global_position = spawn_pos

		if a_map != null:
			unit.update_commands(_release_commands(unit, a_owner_cmd, a_map, spawn_pos))


## The longest reach any occupant has against one targetable layer, extended by this
## garrison's bonus, so it matches what bunker fire can actually reach (it is measured from
## the HOST's footprint, like every range); -1.0 when no occupant reaches that layer. Only a
## BUNKER's occupants fire, so a hold full of enemy prisoners (a stock truck) lends its captor
## nothing.
func occupant_reach_on_layer(a_layer: int) -> float:
	var owner_cmd := get_parent() as Actor
	if not bunker or owner_cmd == null:
		return -1.0
	var best: float = -1.0
	for unit: Actor in _garrisoned:
		if unit.weapon_inventory == null:
			continue
		for weapon: Weapon in unit.weapon_inventory.get_weapons():
			var reach: float = weapon.reach_on_layer(a_layer)
			if reach >= 0.0:
				best = maxf(best, reach + reach_bonus_for(unit, reach))
	return best


## How far `a_unit`'s weapon, whose own reach is `a_reach`, fires beyond that reach out of
## this garrison: up to its [member reach_by_piece] entry when it has one, otherwise
## [member range_bonus].
func reach_bonus_for(a_unit: Actor, a_reach: float) -> float:
	if a_unit != null and reach_by_piece.has(a_unit.id):
		return maxf(0.0, reach_by_piece[a_unit.id] - a_reach)
	return range_bonus


## Re-derive the host's aggro from its occupants — see Actor.reach_on_layer.
func _refresh_aggro_range() -> void:
	var owner_cmd := get_parent() as Actor
	if bunker and owner_cmd != null:
		owner_cmd.refresh_aggro_shapes()


## Safety net: free any garrisoned units that are still orphaned when this component
## is freed (i.e. when the host dies and neither evacuate() nor kill_occupants() had
## already cleared them). In-tree units are left untouched.
func _notification(a_what: int) -> void:
	if a_what == NOTIFICATION_PREDELETE:
		for unit: Actor in _garrisoned:
			if is_instance_valid(unit) and not unit.is_inside_tree():
				unit.free()


## Evacuation path for garrison owners that do NOT occupy the terrain grid
## (e.g. units). Garrisoned units are spread around the owner via
## _spread_points — each gets a distinct point clear of existing bodies and on
## valid navmesh — then issued a movement command to that spawn position so
## the command clears immediately.
func _evacuate_from_unit(a_owner_cmd: Actor, a_map: Map) -> void:
	var count := _garrisoned.size()
	if count == 0:
		return
	var center := VU.in_xz(a_owner_cmd.global_position)
	# Bias the cluster toward the destination the evacuees are sent to (the host's
	# rally_destination — e.g. a transport passing on its heading), so they disembark
	# on that side. Mirrors Production._spawn_unit's rally bias.
	var rally: MoveCommand = a_owner_cmd.rally_destination()
	if rally != null:
		var to_dest: Vector2 = VU.in_xz(rally.message.position) - center
		if not to_dest.is_zero_approx():
			center += to_dest.normalized()
	# Space each evacuee by its own radius rather than the (often larger) transport's.
	var points: Array[Vector2] = _spread_points(
		a_map, center, _evacuee_radii(), a_map.get_world_3d() if a_map != null else null, count
	)

	for i in range(count):
		var unit: Actor = _garrisoned[i]
		var spawn_xz: Vector2 = points[i]
		var height_offset: float = unit.height_offset()
		var y: float = (
			a_map.terrain_height_at(spawn_xz) + height_offset
			if a_map != null
			else a_owner_cmd.global_position.y
		)
		var spawn_pos := Vector3(spawn_xz.x, y, spawn_xz.y)

		if not _return_to_commander(unit):
			continue
		_restore_loadout(unit)
		unit.global_position = spawn_pos

		if a_map != null:
			unit.update_commands(_release_commands(unit, a_owner_cmd, a_map, spawn_pos))


## Generate `count` distinct XZ points around `center`, each snapped to valid
## navmesh and clear of existing MOVEMENT_OBSTRUCTION bodies — via
## SpaceUtils.get_nonoverlapping_points — so units released together (from a
## structure or a mobile host) don't land stacked on the same frame. Falls
## back to fanning any shortfall (crowded area, or no map) out on a ring of
## distinct angles around `center`; physics resolves any residual overlap.
static func _spread_points(
	map: Map, center: Vector2, point_radii: Array[float], world_3d: World3D, count: int
) -> Array[Vector2]:
	var points: Array[Vector2] = []
	if map != null and not point_radii.is_empty():
		# No maximum spread radius: per-unit spacing (point_radii) already keeps the
		# release tight, so let the sampler place points wherever it finds free
		# navmesh rather than rejecting any that fall past a fixed cap.
		var region_radius: float = INF
		points = SU.get_nonoverlapping_points(
			map,
			center,
			point_radii[0],
			world_3d,
			CollisionLayers.Mask.MOVEMENT_OBSTRUCTION,
			region_radius,
			count,
			10,
			point_radii
		)

	while points.size() < count:
		var leftover_index := points.size()
		var angle: float = 2.0 * PI * float(leftover_index) / float(maxi(count, 1))
		# Fan any shortfall out on a ring, sized by that specific unit's radius.
		var r: float = point_radii[leftover_index] if leftover_index < point_radii.size() else 0.5
		var ring_radius: float = 2.0 * r * (1.0 + float(leftover_index) / float(maxi(count, 1)))
		points.append(center + Vector2(cos(angle), sin(angle)) * ring_radius)

	return points


## Per-occupant MOVEMENT_OBSTRUCTION radius, in _garrisoned order, so evacuation
## can space each released unit by its own footprint. Occupants are units, so they
## carry a MovementBody and bounding_radius is valid; a body-less occupant would
## simply report 0 and pack tight.
func _evacuee_radii() -> Array[float]:
	var radii: Array[float] = []
	for unit: Actor in _garrisoned:
		radii.append(unit.bounding_radius(CollisionLayers.Mask.MOVEMENT_OBSTRUCTION))
	return radii


## The command chain a released unit gets on evacuation: first the immediate exit-point move
## (`a_dest`) so it clears the host without overlapping it, then whatever it should do next.
##
## WHAT IT DOES NEXT IS ITS OWN ORDERS IF IT HAS ANY, and the host's rally otherwise. This is
## the same precedence a trained unit gets between a player order and its producer's rally,
## and for the same reason: "I told THAT unit to go there" is more specific than "everything
## that comes out of here goes there".
##
## A garrisoned unit is OFF THE TREE, so it never processes a command while it is inside —
## orders given to a selected occupant simply sit in its queue, and this is where they are
## picked up again. A unit that never comes out never acts on them, which is the whole of
## what happens in that case.
##
## Each evacuee gets its own copies, so a group released together doesn't share instances.
static func _release_commands(
	a_unit: Actor, a_owner_cmd: Actor, a_map: Map, a_dest: Vector3
) -> Array[MoveCommand]:
	var commands: Array[MoveCommand] = [
		MoveCommand.new(CommandMessage.new(a_map, null, null, a_dest))
	]
	var own: Array[MoveCommand] = (
		(
			a_unit.command_receiver.get_command_chain()
			if a_unit != null and a_unit.command_receiver != null
			else []
		)
		as Array[MoveCommand]
	)
	if not own.is_empty():
		for command: MoveCommand in own:
			commands.append(command.duplicated())
		return commands
	if a_owner_cmd != null:
		commands.append_array(a_owner_cmd.rally_chain())
	return commands
#endregion
