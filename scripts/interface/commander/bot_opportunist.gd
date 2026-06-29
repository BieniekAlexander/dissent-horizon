class_name BotOpportunist
extends RefCounted

## BotOpportunist — the bot's opportunistic, utility-driven decision layer.
##
## Each think it gathers candidate [BotOpportunity]s from every registered domain
## gatherer, ranks them by utility (net ore-equivalent gain), and executes the best
## ones — capped at one action per actor per tick so a single unit isn't handed two
## jobs at once. Liberation (Warlords freeing Shelters) is the first such decision;
## adding another is a new gatherer that returns scored opportunities, nothing else.

## Ore-equivalent value of one imprisoned unit — its dominion contribution over its
## stay in an internment camp, used to score the capture / collect / deposit loop. A
## balance knob; raise to make the bot prize the dominion economy more.
const PRISONER_VALUE: float = 60.0

var _bot: Bot
var _act: BotActuator

## Domain gatherers — each returns Array[BotOpportunity] of currently-available, scored
## actions. Register a new utility decision by appending its gatherer here.
var _gatherers: Array[Callable] = []


## True when `unit` is currently carrying out a committed opportunity action (right now,
## liberating a Shelter via an Interact command). The combat managers treat such a unit
## as busy and leave it alone — exactly as they do a unit mid-construction — so the
## action runs to completion instead of being overridden by attack/scout tasking each
## think. New committed opportunity kinds should extend this predicate.
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
		_gather_abductions,
		_gather_collections,
		_gather_deposits,
		_gather_garrison_orders,
	]


func tick() -> void:
	var candidates: Array[BotOpportunity] = []
	for gather: Callable in _gatherers:
		candidates.append_array(gather.call())
	# Only act on net-positive opportunities, best first.
	candidates = candidates.filter(func(o: BotOpportunity): return o.utility() > 0.0)
	candidates.sort_custom(func(a: BotOpportunity, b: BotOpportunity): return a.utility() > b.utility())
	# Greedy: take the highest-utility action available to each still-free actor.
	var claimed: Dictionary = {}  # actor -> true
	for o: BotOpportunity in candidates:
		if claimed.has(o.actor):
			continue
		o.execute(_act)
		claimed[o.actor] = true


# ─── LIBERATION ──────────────────────────────────────────────────────────────

## One opportunity per available shelter: pair it with the nearest free Interactor unit
## (a Warlord) and score it by the value of the units the liberation would spawn for us.
## Conflicts (two shelters picking the same warlord) resolve in tick() — the higher
## utility wins the warlord, the other shelter waits for a future think.
func _gather_liberations() -> Array[BotOpportunity]:
	var out: Array[BotOpportunity] = []
	var liberators: Array = _free_liberators()
	if liberators.is_empty():
		return out
	for shelter: Entity in _bot.get_available_shelters():
		var warlord: Commandable = _nearest(liberators, shelter.global_position)
		if warlord == null:
			continue
		var interaction: Interaction = _liberation_interaction(warlord, shelter)
		if interaction == null:
			continue
		var value: float = _bot.interaction_spawn_value(interaction)
		if value <= 0.0:
			continue
		out.append(LiberationOpportunity.new(warlord, shelter, value))
	return out


## Interactor units not already busy liberating — free to be tasked. A warlord
## mid-liberation (or walking to a shelter) keeps its Interact command instead of being
## re-issued every think.
func _free_liberators() -> Array:
	return _bot.get_interactors().filter(
		func(u: Commandable): return not (u.current_command() is Interact)
	)


## The interaction `warlord` would perform on `shelter`, or null — resolved through the
## unit's own Interactor so it honours the exact applicability rules a player click does
## (matching interaction type, shelter available).
func _liberation_interaction(warlord: Commandable, shelter: Entity) -> Interaction:
	if warlord.interactor == null:
		return null
	return warlord.interactor.applicable_interaction(warlord, CommandMessage.new(_bot.map, shelter))


func _nearest(units: Array, world_pos: Vector3) -> Commandable:
	var best: Commandable = null
	var best_d: float = INF
	for u: Commandable in units:
		var d: float = u.global_position.distance_squared_to(world_pos)
		if d < best_d:
			best_d = d
			best = u
	return best


# ─── COLONIAL DOMINION LOOP (capture → collect → deposit) ────────────────────
# A faction-agnostic, interaction-driven dominion economy: units that can ABDUCT /
# COLLECT / DEPOSIT (the Stock Truck) fill up on prisoners and bank them in a
# structure that turns them into dominion (the internment camp). Each step is a
# scored InteractOpportunity, so it competes on the same utility scale as everything
# else. Capture/collect are gated on owning a camp with space — no point hoarding
# prisoners with nowhere to bank them (the economy builds the camp first).

## Interactor units free to take on a new errand — not mid-build or mid-interaction.
func _free_carriers() -> Array:
	return _bot.get_interactors().filter(func(u: Commandable) -> bool:
		var c: Command = u.current_command()
		return not (c is Interact or c is Build or c is Repair)
	)

## True when `carrier` resolves the expected interaction `kind` on `target` — routed
## through its own Interactor so it honours the same applicability a player click does.
func _resolves(carrier: Commandable, target: Entity, kind: Interaction.Type) -> bool:
	if carrier.interactor == null:
		return false
	var interaction: Interaction = carrier.interactor.applicable_interaction(carrier, CommandMessage.new(_bot.map, target))
	return interaction != null and interaction.type == kind

## Send a carrier with free space to imprison a visible enemy biological unit. Valued
## at the prisoner's dominion worth plus a denial bonus (half the captured unit's cost).
func _gather_abductions() -> Array[BotOpportunity]:
	var out: Array[BotOpportunity] = []
	if _bot.get_deposit_structures().is_empty():
		return out
	var carriers: Array = _free_carriers().filter(
		func(u: Commandable): return u.ability_inventory != null and u.ability_inventory.can_hold_more()
	)
	if carriers.is_empty():
		return out
	for enemy: Commandable in _bot.get_capturable_enemies():
		var carrier: Commandable = _nearest(carriers, enemy.global_position)
		if carrier == null or not _resolves(carrier, enemy, Interaction.Type.ABDUCT):
			continue
		var value: float = PRISONER_VALUE + 0.5 * float(_bot.unit_cost(enemy.type))
		out.append(InteractOpportunity.new(carrier, enemy, value, "abduct"))
	return out

## Send a carrier with free space to a ready Shelter to collect prisoners into its hold.
## Valued at the dominion worth of the units it would load (clamped to free space).
func _gather_collections() -> Array[BotOpportunity]:
	var out: Array[BotOpportunity] = []
	if _bot.get_deposit_structures().is_empty():
		return out
	var carriers: Array = _free_carriers().filter(
		func(u: Commandable): return u.ability_inventory != null and u.ability_inventory.can_hold_more()
	)
	if carriers.is_empty():
		return out
	for shelter: Entity in _bot.get_available_shelters():
		var carrier: Commandable = _nearest(carriers, shelter.global_position)
		if carrier == null:
			continue
		var interaction: Interaction = carrier.interactor.applicable_interaction(carrier, CommandMessage.new(_bot.map, shelter)) \
			if carrier.interactor != null else null
		if interaction == null or interaction.type != Interaction.Type.COLLECT:
			continue
		var space: int = carrier.ability_inventory.item_capacity - carrier.ability_inventory.item_count()
		var value: float = float(mini(interaction.payload_count, space)) * PRISONER_VALUE
		out.append(InteractOpportunity.new(carrier, shelter, value, "collect"))
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
		var inv: Inventory = carrier.ability_inventory
		if inv == null or not inv.has_items():
			continue
		var c: Command = carrier.current_command()
		if c is Interact or c is Build or c is Repair:
			continue
		var camp: Commandable = _nearest(camps, carrier.global_position)
		if camp == null or not _resolves(carrier, camp, Interaction.Type.DEPOSIT):
			continue
		# Worth the dominion the carried prisoners will bank. Travel-free (weight 0) so a
		# truck that captured deep in enemy territory still heads home to deposit rather
		# than wandering until it dies with its load. A full truck scores highest (it
		# can't capture more), so partially-loaded trucks prefer to keep filling first.
		var full: bool = not inv.can_hold_more()
		var value: float = float(inv.item_count()) * PRISONER_VALUE * (1.5 if full else 1.0)
		out.append(InteractOpportunity.new(carrier, camp, value, "deposit", 0.0))
	return out


# ─── GARRISON (bunker fire support) ─────────────────────────────────────────

## Send idle combat units that are close to a bunker garrison structure inside
## it, where they can continue to fire while being protected. Only bunker
## structures are targeted — non-bunker garrisons offer protection but no added
## combat value, so they're left for the preservation retreat path instead.
func _gather_garrison_orders() -> Array[BotOpportunity]:
	var out: Array[BotOpportunity] = []
	var hosts: Array = _bot.get_garrison_structures().filter(
		func(s: Commandable) -> bool: return s.garrison.bunker
	)
	if hosts.is_empty():
		return out
	var candidates: Array = _bot.get_idle_units().filter(
		func(u: Commandable) -> bool:
			return u.movement != null \
				and u.movement.mode == Movement.Mode.GROUNDED_DIRECT \
				and u.weapon_inventory != null \
				and u.weapon_inventory.has_weapons() \
				and not is_committed(u) \
				and not BotEconomy._is_constructing(u)
	)
	if candidates.is_empty():
		return out
	for host: Commandable in hosts:
		var nearest: Commandable = _nearest(candidates, host.global_position)
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
func _bunker_garrison_utility(unit: Commandable, distance: float) -> float:
	var attack_value: float = unit.weapon_inventory.total_damage() \
		if unit.weapon_inventory != null else 0.0
	return attack_value - distance * 0.5
