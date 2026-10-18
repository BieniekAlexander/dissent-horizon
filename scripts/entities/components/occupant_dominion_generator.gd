class_name OccupantDominionGenerator
extends DominionGenerator

## THE PRISON: everything the Compound does with what its Garrison holds. A host carrying this
## generator is where captives are DEPOSITED (is_prison), and each one SERVES a sentence — one
## at a time, in arrival order — banking `dominion_per_unit` per tick cycle while it serves and
## CONSUMED at the end of it, which also takes a slice off the cooldowns of the host's
## neighbours (Work Detail). gdd/systems/combat/colonial-dominion.md §A captive serves a sentence.
##
## The Garrison knows none of this: it holds, captures and releases, and says when an occupant
## enters or leaves (Garrison.occupant_entered / occupant_left). Every prison rule lives here,
## and is a constant rather than a doc key, because the Compound is the one building that runs
## it.
##
## Counts OCCUPANTS, not occupancy size: a prisoner is worth the same however bulky it is, so a
## large captive filling two of the camp's slots still banks one unit's worth.
##
## Subclasses DominionGenerator and is named "DominionGenerator" in the scene so Actor's
## existing `dominion_generator` hook ticks it with no extra wiring.

#region Constants
## Seconds a deposited captive serves before being consumed. Calibrated 2026-10-05 against the
## Technocratic Lab route (gdd/systems/macroeconomics/pacing/dominion-rate-analysis.md §One-at-a-
## time processing). A constant: the Compound is the only prison, so there is no second value to
## author.
const SENTENCE_SECONDS: float = 30.0

## How many captives serve at once. ONE: the rest of the places hold captives waiting their
## turn, paying nothing and with their terms not yet started. Named so the throughput
## projection (Commander.projected_dominion_rate) reads the same number this file obeys.
const SENTENCES_AT_ONCE: int = 1

## What one adjacent structure's ability pools have their cooldown reduced by, on each sentence
## completing here — a fraction of the pool's own FULL cooldown, not of its remaining time (see
## colonial-dominion.md §The positional bonus is an event, not a rate). Work Detail's number.
const SENTENCE_COOLDOWN_BONUS: float = 0.08
#endregion

#region Properties
## Dominion awarded per paying occupant, per TICK_RATE cycle (every 5 seconds): 5/s, so a
## captive serving the Compound's 30 s sentence is worth 150. Set 2026-10-05 together with
## one-at-a-time sentencing, which puts the Colonial route at about the Technocratic Lab route's
## rate (gdd/systems/macroeconomics/pacing/dominion-rate-analysis.md §Colonial decision).
@export var dominion_per_unit: int = 25

## The whole prison switched off: the host takes no deposits, sentences nobody and banks
## nothing, so what it holds stays until freed. The one-off a mission sets on its own camp,
## where the enemy's prisoners are the player's to free. The game's own camp never sets it.
@export var is_disabled: bool = false

## Seconds remaining on each occupant's sentence, keyed by unit, in arrival order. The first
## SENTENCES_AT_ONCE keys are the ones serving; insertion order is the queue, which is why
## nothing may rebuild this Dictionary out of order.
var _sentence_remaining: Dictionary = {}
#endregion


#region Lifecycle
func _ready() -> void:
	var garrison: Garrison = _garrison()
	if garrison == null:
		return
	garrison.occupant_entered.connect(_on_occupant_entered)
	garrison.occupant_left.connect(_on_occupant_left)


## Nothing to step until a captive starts a sentence (Garrison.garrison wakes the host then),
## and nothing ever while switched off.
func sleep_ticks() -> int:
	return Entity.SLEEP_FOREVER if is_disabled or _sentence_remaining.is_empty() else 0


## A switched-off prison never pays, so the host need not wake for its cycle.
func ticks_before_payout() -> int:
	return Entity.SLEEP_FOREVER if is_disabled else super()


## Count the serving captives' terms down, consuming each whose term is up. A term that ends
## mid-step does not hand its leftover to the next captive — the next one starts on the
## following tick.
func simulation_step(a_delta: float) -> void:
	if is_disabled or _sentence_remaining.is_empty():
		return
	# Snapshot the serving keys: consuming a captive leaves the garrison, which erases it here.
	for unit: Variant in _sentence_remaining.keys().slice(0, SENTENCES_AT_ONCE):
		if not is_instance_valid(unit):
			_sentence_remaining.erase(unit)
			continue
		_sentence_remaining[unit] -= a_delta
		if _sentence_remaining[unit] <= 0.0:
			_sentence_remaining.erase(unit)
			_garrison().discard(unit)
			_emit_positional_bonus()


#endregion


#region Public API
## The prison on `host`, or null when it has none (or has one switched off): what DEPOSIT and
## the bot ask to tell a camp from a safehouse.
static func prison_of(host: Node) -> OccupantDominionGenerator:
	if host == null:
		return null
	var generator := host.get_node_or_null("DominionGenerator") as OccupantDominionGenerator
	return generator if generator != null and not generator.is_disabled else null


## Whether this prison has room for one more deposited captive — the precondition for
## Interaction DEPOSIT. Room is asked as one slot of the smallest size, matching every other
## unconsented entry; keep captured pieces at size 1.
func can_intern() -> bool:
	var garrison: Garrison = _garrison()
	return not is_disabled and garrison != null and garrison.can_garrison()


## Seconds left on `a_unit`'s sentence, or -1 when it is not serving one here.
func sentence_remaining(a_unit: Actor) -> float:
	return float(_sentence_remaining.get(a_unit, -1.0))


## The captives SERVING right now — at most SENTENCES_AT_ONCE; the ones waiting their turn do
## not pay.
func paying_count() -> int:
	return mini(_sentence_remaining.size(), SENTENCES_AT_ONCE)


## Overrides DominionGenerator.tick: award per-prisoner dominion each cycle instead
## of a flat rate. No-op cycles when the garrison is empty.
func tick() -> void:
	if is_disabled:
		return
	ticks_elapsed += 1
	if ticks_elapsed < TICK_RATE:
		return
	ticks_elapsed = 0
	var parent := get_parent() as Entity
	if parent == null or parent.commander == null:
		return
	var held: int = paying_count()
	if held > 0:
		parent.commander.add_dominion(dominion_per_unit * held)
		build_up += 1


## Per HEAD, matching what tick() actually pays out.
func payout() -> int:
	return 0 if is_disabled else dominion_per_unit * contributor_count()


## The prisoners this camp is paying for — what the Colonial dominion rate is made OF, so the
## economy readout can say "+5/s · 1 captive" rather than just "+5/s". Head count of the
## captives SERVING, matching what tick() actually pays out (a bulky captive is worth one
## prisoner, not two; a captive waiting its turn is worth nothing yet).
func contributor_count() -> int:
	return 0 if is_disabled else paying_count()


#endregion


#region Internal
func _garrison() -> Garrison:
	var parent: Node = get_parent()
	return parent.get_node_or_null("Garrison") as Garrison if parent != null else null


## Every arrival starts a fresh term — a deposited captive, and a Servant riding in with it.
func _on_occupant_entered(a_unit: Actor) -> void:
	if not is_disabled:
		_sentence_remaining[a_unit] = SENTENCE_SECONDS


## Whoever leaves takes no term with them: freed by an order, the host's death, a flush, or the
## sentence itself (already erased).
func _on_occupant_left(a_unit: Actor) -> void:
	_sentence_remaining.erase(a_unit)


## On a sentence completing, reduce the cooldown of every ability pool on every edge-adjacent
## structure of its own by SENTENCE_COOLDOWN_BONUS — Work Detail, carried by whichever piece
## grants it (Abilities.SUPPORT_ABILITY). The three things that switch it off are asked of the
## SUPPORTER (this host, the Compound): it must be finished, and its commander's infrastructure
## must cover its upkeep. Nothing beyond ownership is asked of the structure being helped.
func _emit_positional_bonus() -> void:
	var host := get_parent() as Actor
	if (
		host == null
		or host.map == null
		or not host.is_built
		or host.is_defective()
		or not _grants_positional_bonus(host)
	):
		return
	for neighbor: Entity in SU.edge_adjacent_structures(host.map, host):
		var supported := neighbor as Actor
		# The host's OWN structures: an ally shares vision, repair and friendly-target abilities,
		# not passive bonuses (target-acquisition.md §Alliances).
		if supported == null or supported.commander_id != host.commander_id:
			continue
		var pool := supported.get_node_or_null("Abilities") as Abilities
		if pool != null:
			pool.reduce_all_cooldowns(SENTENCE_COOLDOWN_BONUS)


static func _grants_positional_bonus(a_host: Actor) -> bool:
	var pool := a_host.get_node_or_null("Abilities") as Abilities
	return pool != null and pool.grants(Abilities.SUPPORT_ABILITY)
#endregion
