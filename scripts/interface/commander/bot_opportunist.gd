class_name BotOpportunist
extends RefCounted

## BotOpportunist — the bot's opportunistic, utility-driven decision layer.
##
## Each think it gathers candidate [BotOpportunity]s from every registered domain
## gatherer, ranks them by utility (net energy-equivalent gain), and executes the best
## ones — capped at one action per actor per tick so a single unit isn't handed two
## jobs at once. Liberation (Warlords converting a Shelter's Terrestrials) is the first
## such decision; adding another is a new gatherer that returns scored opportunities,
## nothing else.

## Energy-equivalent value of one imprisoned unit — its dominion contribution over its
## stay in a Compound, used to score the capture / collect / deposit loop. A
## balance knob; raise to make the bot prize the dominion economy more.
const PRISONER_VALUE: float = 60.0

var _bot: Bot
var _act: BotActuator

## The bot's own seeded stream (BotBrain.rng), for the order errands are taken in; null
## makes it best-first exactly.
var rng: RandomNumberGenerator = null
## How willing the ordering is to put a near-best errand first (BotDifficulty).
var decision_temperature: float = 0.0

## Domain gatherers — each returns Array[BotOpportunity] of currently-available, scored
## actions. Register a new utility decision by appending its gatherer here.
var _gatherers: Array[Callable] = []

## The owner name this module claims errand units under (BotClaims). An errand runs to
## completion, so the army's rally leaves the unit alone until it does.
const CLAIM_OWNER: StringName = &"opportunist"

## Which manager owns which unit; the brain replaces this with the bot's shared registry. A
## fresh one by default, so a bare manager in a test sees every unit unclaimed.
var claims: BotClaims = BotClaims.new()

## Work units per opportunity gathered and ranked, and the fixed cost of the gatherers' own scans
## (BotScheduler counts work in units of roughly a microsecond on the calibration machine).
const OPPORTUNITY_WORK_UNITS: int = 3
const GATHER_WORK_UNITS: int = 12


## True when `unit` is currently carrying out a committed opportunity action (right now,
## an Interact errand: depositing or planting). The combat managers treat
## such a unit as busy and leave it alone — exactly as they do a unit mid-construction —
## so the action runs to completion instead of being overridden by attack/scout tasking
## each think. New committed opportunity kinds should extend this predicate.
##
## NOTE: the CONTACT errands — liberation and capture — are deliberately NOT covered. Each
## is a plain move order, indistinguishable from any other, so the combat managers may
## retask a warlord walking toward a terrestrial or a truck running down a soldier. Both
## re-gather on the next think.
static func is_committed(unit: Commandable) -> bool:
	return unit.has_command() and unit.current_command() is Interact


## Maximum distance (world units) a unit may be from a bunker structure for the
## bot to consider garrisoning it there proactively.
const GARRISON_CONSIDER_RADIUS: float = 30.0


func _init(a_bot: Bot, a_act: BotActuator) -> void:
	_bot = a_bot
	_act = a_act
	_gatherers = [
		_gather_liberations,
		_gather_captures,
		_gather_deposits,
		_gather_garrison_orders,
	]


## Returns the work units spent.
func tick() -> int:
	_release_finished_errands()
	var candidates: Array[BotOpportunity] = []
	for gather: Callable in _gatherers:
		candidates.append_array(gather.call())
	var work: int = (
		GATHER_WORK_UNITS * _gatherers.size() + candidates.size() * OPPORTUNITY_WORK_UNITS
	)
	# A unit another manager holds as strongly (a builder on a job, a kamikaze drone) is not ours
	# to send, however good the errand.
	candidates = candidates.filter(
		func(o: BotOpportunity) -> bool:
			return claims.can_claim(o.actor, CLAIM_OWNER, BotClaims.Priority.ERRAND)
	)
	# Only act on net-positive opportunities, best first — "first" drawn at the bot's
	# temperature, so which of two close errands gets the shared actor varies by match.
	candidates = candidates.filter(func(o: BotOpportunity): return o.utility() > 0.0)
	var utilities: Array = candidates.map(func(o: BotOpportunity) -> float: return o.utility())
	var ordered: Array[BotOpportunity] = []
	for i: int in BotSampling.order(utilities, decision_temperature, rng):
		ordered.append(candidates[i])
	candidates = ordered
	# Greedy: take the highest-utility action available to each still-free actor.
	var claimed: Dictionary = {}  # actor -> true
	for o: BotOpportunity in candidates:
		if claimed.has(o.actor):
			continue
		o.execute(_act)
		claimed[o.actor] = true
		claims.claim(o.actor, CLAIM_OWNER, BotClaims.Priority.ERRAND)
	return work


## Give back every unit whose errand is over: it has arrived (no command left) or gone into the
## garrison it was sent to.
func _release_finished_errands() -> void:
	for unit: Variant in claims.units_of(CLAIM_OWNER):
		if (
			not is_instance_valid(unit)
			or not (unit as Commandable).has_command()
			or (unit as Commandable).is_garrisoned()
		):
			claims.release(unit, CLAIM_OWNER)


# ─── LIBERATION ──────────────────────────────────────────────────────────────


## One opportunity per loose neutral Terrestrial: pair it with the nearest free
## [Liberator] unit (a Warlord) and score it by what the conversion yields us. There
## is no command to issue — conversion is passive on contact (see Liberator) — so the
## opportunity is just a walk over there. Conflicts (two terrestrials picking the same
## warlord) resolve in tick(): the higher utility wins, the other waits for a future
## think.
func _gather_liberations() -> Array[BotOpportunity]:
	var out: Array[BotOpportunity] = []
	var liberators: Array = _free_liberators()
	if liberators.is_empty():
		return out
	for terrestrial: Commandable in _bot.get_neutral_terrestrials():
		var warlord: Commandable = _nearest(liberators, terrestrial.global_position)
		if warlord == null:
			continue
		var value: float = _bot.liberation_value(warlord)
		if value <= 0.0:
			continue
		out.append(ContactOpportunity.new(warlord, terrestrial, value, "liberate"))
	return out


## Liberator units free to be tasked. Unlike the old shelter interaction, a liberation
## errand is a plain move order, so "already on one" isn't visible in the command type —
## an unoccupied (commandless) warlord is the one we're willing to send. A warlord
## already walking to a terrestrial keeps that move command and is skipped here.
func _free_liberators() -> Array:
	return _bot.get_liberators().filter(func(u: Commandable): return not u.has_command())


func _nearest(a_units: Array, a_world_pos: Vector3) -> Commandable:
	var best: Commandable = null
	var best_d: float = INF
	for u: Commandable in a_units:
		var d: float = u.global_position.distance_squared_to(a_world_pos)
		if d < best_d:
			best_d = d
			best = u
	return best


# ─── COLONIAL DOMINION LOOP (capture → deposit) ─────────────────────────────
# A faction-agnostic dominion economy: a carrier with a hold (the Stock Truck) fills up on
# prisoners and banks them in a structure that turns them into dominion (the Compound).
# Each step is a scored opportunity, so it competes on the same utility scale as everything
# else — a CAPTURE is a ContactOpportunity (driving over the prey IS the mechanic; see
# Garrison.can_capture) and a DEPOSIT is an InteractOpportunity. Capture is gated on owning
# a camp with space — no point hoarding prisoners with nowhere to bank them (the economy
# builds the camp first).


## Carrier units free to take on a capture errand. A capture is a plain MOVE order, so
## "already on one" is not visible in the command type — an idle carrier is the one we are
## willing to send, exactly as for a liberation (see _free_liberators). A carrier already
## driving at prey keeps its move and is skipped here rather than being re-aimed every think.
##
## A carrier on ARMY DUTY (an AttackMove) is free too. BotMilitary sweeps idle trucks into
## the army so they crush infantry rather than stand still — but an AttackMove never ends by
## itself, so an idle-only test meant a truck once swept up never took another errand, and
## the bot's captures stopped for the rest of the match.
func _free_carriers() -> Array:
	return _bot.get_interactors().filter(
		func(u: Commandable) -> bool:
			return not u.has_command() or u.current_command() is AttackMove
	)


## True when `carrier` resolves the expected interaction `kind` on `target` — routed
## through its own Interactor so it honours the same applicability a player click does.
func _resolves(a_carrier: Commandable, a_target: Entity, a_kind: Interaction.Type) -> bool:
	if a_carrier.interactor == null:
		return false
	var interaction: Interaction = a_carrier.interactor.applicable_interaction(
		a_carrier, CommandMessage.new(_bot.map, a_target)
	)
	return interaction != null and interaction.type == a_kind


## Send a carrier with free space to run down a capturable biological unit — a visible
## enemy soldier, or one of a Shelter's neutral Terrestrials. Valued at the prisoner's
## dominion worth plus a denial bonus of half the captured unit's cost; a neutral costs
## nothing, so taking one is worth exactly its dominion.
##
## The errand is a plain move: capture happens on CONTACT (Garrison.can_capture), so the
## rule is asked directly rather than through an Interactor. Carriers are filtered on
## remaining capacity, so the bot never sets out on a capture it cannot complete — a full
## truck that drives over prey anyway simply crushes it, which is not something to seek out.
func _gather_captures() -> Array[BotOpportunity]:
	var out: Array[BotOpportunity] = []
	if _bot.get_deposit_structures().is_empty():
		return out
	var carriers: Array = _free_carriers().filter(
		func(u: Commandable): return u.garrison != null and u.garrison.remaining_capacity() > 0
	)
	if carriers.is_empty():
		return out
	var candidates: Array = _bot.get_capturable_enemies() + _bot.get_neutral_terrestrials()
	for prey: Commandable in candidates:
		var carrier: Commandable = _nearest(carriers, prey.global_position)
		if carrier == null or not Garrison.can_capture(carrier, prey):
			continue
		var value: float = PRISONER_VALUE + 0.5 * float(_bot.unit_cost(prey.id))
		out.append(ContactOpportunity.new(carrier, prey, value, "capture"))
	return out


## Send a carrier holding prisoners to the nearest owned deposit structure (camp) with
## space. A full carrier's deposit is worth the most (it can't capture more until it
## unloads); a partial one is discounted so carriers prefer to keep filling first.
func _gather_deposits() -> Array[BotOpportunity]:
	var out: Array[BotOpportunity] = []
	var camps: Array = _bot.get_deposit_structures()
	if camps.is_empty():
		return out
	for carrier: Commandable in _bot.get_interactors():
		var cage: Garrison = carrier.garrison
		if cage == null or cage.garrisoned_count() == 0:
			continue
		var c: MoveCommand = carrier.current_command()
		if c is Interact or c is Build or c is Assemble or c is Repair:
			continue
		var camp: Commandable = _nearest(camps, carrier.global_position)
		if camp == null or not _resolves(carrier, camp, Interaction.Type.DEPOSIT):
			continue
		# Worth the dominion the carried prisoners will bank. Travel-free (weight 0) so a
		# truck that captured deep in enemy territory still heads home to deposit rather
		# than wandering until it dies with its load. A full truck scores highest (it
		# can't capture more), so partially-loaded trucks prefer to keep filling first.
		var full: bool = cage.remaining_capacity() <= 0
		var value: float = float(cage.garrisoned_count()) * PRISONER_VALUE * (1.5 if full else 1.0)
		out.append(InteractOpportunity.new(carrier, camp, value, "deposit", 0.0))
	return out


# ─── GARRISON (bunker fire support) ─────────────────────────────────────────


## Send idle combat units that are close to a bunker inside it, where they fire from cover.
## The hosts are the bot's own bunkers AND the neutral buildings (Bot.get_bunker_hosts):
## until 2026-10-04 only owned hosts were considered, and the Colonials own no open bunker
## at all, so the bot never garrisoned anything. Non-bunker garrisons offer protection but
## no fire, so they are left for the preservation retreat path. The wave collects bunkered
## units when it launches (BotMilitary evacuates the hosts holding them).
func _gather_garrison_orders() -> Array[BotOpportunity]:
	var out: Array[BotOpportunity] = []
	var hosts: Array = _bot.get_bunker_hosts()
	if hosts.is_empty():
		return out
	var candidates: Array = _bot.get_idle_units().filter(
		func(u: Commandable) -> bool:
			return (
				u.movement != null
				and u.movement.mode == Movement.Mode.GROUNDED
				and u.weapon_inventory != null
				and u.weapon_inventory.has_weapons()
				and not is_committed(u)
				and not BotEconomy._is_constructing(u)
			)
	)
	if candidates.is_empty():
		return out
	for host: Commandable in hosts:
		# Only units this host's occupancy masks admit — a hangar-style bunker that takes
		# only aircraft must not be offered the nearest infantryman.
		var admitted: Array = candidates.filter(
			func(u: Commandable) -> bool: return host.garrison.accepts(u)
		)
		var nearest: Commandable = _nearest(admitted, host.global_position)
		if nearest == null:
			continue
		var dist: float = nearest.global_position.distance_to(host.global_position)
		if dist > GARRISON_CONSIDER_RADIUS:
			continue
		var utility: float = _bunker_garrison_utility(nearest, dist)
		out.append(GarrisonOpportunity.new(nearest, host, utility))
	return out


## Utility of garrisoning [unit] into a bunker: its weapon output minus a small
## travel cost so nearby units are preferred over distant ones.
func _bunker_garrison_utility(a_unit: Commandable, a_distance: float) -> float:
	var attack_value: float = (
		a_unit.weapon_inventory.total_damage() if a_unit.weapon_inventory != null else 0.0
	)
	return attack_value - a_distance * 0.5
