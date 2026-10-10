class_name BotProduction
extends RefCounted

## BotProduction — trains the unit that best COUNTERS the believed enemy, with no
## per-unit rules and no cheap-unit bias.
##
## Each idle production building picks the producible unit with the highest
## composition value (Bot.unit_composition_value): effectiveness × per-enemy-type
## demand, where demand is each believed enemy type's importance reduced by how well
## the bot's CURRENT army already counters it. So:
##   • an enemy type the army can't handle (e.g. fliers it can't hit, or massed
##     irregulars only the Kamikaze's AOE answers) has high demand → that counter
##     gets built;
##   • once a threat is covered its demand falls (diminishing returns) → the bot
##     diversifies, and eventually values anti-structure units (warlords) for the
##     longer game, since enemy structures keep a (smaller) standing demand.
##
## Cost is NOT a tiebreaker: the wanted unit is trained when affordable, otherwise
## the building WAITS and saves up rather than spamming a cheaper, weaker unit — the
## fix for the bot drowning in irregulars. With no enemy seen yet, it just masses the
## cheapest unit to field an opening army.

var _bot: Bot
var _act: BotActuator

## The bot's own seeded stream (BotBrain.rng), for the unit choice; null makes it the argmax.
var rng: RandomNumberGenerator = null
## How willing the unit choice is to take a near-best counter (BotDifficulty).
var decision_temperature: float = 0.0

## Energy that must still be banked AFTER a unit is paid for, mirroring BotEconomy.reserve
## (BotDifficulty.economy_reserve; pushed by BotBrain._apply_config).
##
## Training used to spend on plain affordability, which is the reason the reserve knob could
## not do the job the roadmap gives it ("stop the bot spending down to zero so that it can
## always afford something"): the buildings drained the pool to literally zero underneath a
## threshold that only ever looked at BotEconomy's own purchases. A floor that one of the two
## spenders ignores is not a floor. See BotEconomy.can_afford_above_reserve, and
## gdd/systems/ai/bot-economy-diagnosis.md for the measurement.
var reserve: int = 0


func _init(a_bot: Bot, a_act: BotActuator) -> void:
	_bot = a_bot
	_act = a_act


## SAFETY CEILING on how many of each non-combat utility unit (e.g. the Stock Truck) the bot
## maintains. NO LONGER THE DECISION — see _utility_demand_for, which is.
##
## It was both floor and ceiling, and being a floor is what made it wrong: at 3 per type the
## bot built a third Stock Truck when three armed units would have served it better, and
## would never build a fourth when the capture loop was the best energy on the map. A count
## cannot follow the work, and "a utility unit with no errand" is the whole definition of
## too many.
##
## What a ceiling is still FOR: it bounds a demand model whose inputs are counts of things
## on the map, so a map strewn with capturable infantry cannot talk the bot into a fleet of
## trucks. A PARAMETER (BotDifficulty.utility_unit_cap) — 0 removes utility units entirely.
var utility_unit_cap: int = 3

## How many construction jobs the bot runs at once (BotDifficulty.build_concurrency, pushed
## by BotBrain._apply_config). Read here because it IS the builder demand: n concurrent
## builds want n builders, and BotEconomy will pull a fighter off the line for the shortfall.
var build_concurrency: int = 1

## How many units the bot is willing to have away scouting (BotDifficulty.scout_unit_budget).
## Read here because the scout is drawn from THIS pool: BotScout._scout_score picks the unit
## with the fewest live responsibilities, which early on is exactly a utility unit, and the
## ATTACK objective is fog-limited — a bot with nothing spare to look with has no offensive
## at all. See _utility_demand_for for how it enters the demand.
var scout_unit_budget: int = 1

## One body over the live errands. Not slack for its own sake: an errand appears between one
## think and the next (prey wanders into view, a building finishes and frees a site), and a
## bot that sizes exactly to the work it can see always answers one build-time late.
const UTILITY_SPARE: int = 1

## Capture errands as of this tick, or -1 before it has been asked. Clustering is O(n²) over
## visible prey and _best_utility_unit_for runs once per idle producer, so the count is
## computed at most once per think.
var _capture_errands: int = -1

## Work units for reading the enemy demand map, and per idle producer decided for (BotScheduler
## counts work in units of roughly a microsecond on the calibration machine).
const DEMAND_WORK_UNITS: int = 300
const PRODUCER_WORK_UNITS: int = 230


## Returns the work units spent.
func tick() -> int:
	_capture_errands = -1  # recomputed lazily, at most once per think
	var demand: Dictionary = _bot.enemy_demand_map()
	var producers: Array = _bot.get_idle_production_structures()
	var infrastructure_producer: Actor = _train_infrastructure_unit(producers)
	var wanted: Array = []  # [producer, type] for every combat pick, to propose before spending
	for s: Actor in producers:
		if s == infrastructure_producer:
			continue
		wanted.append([s, _best_unit_for(s, demand)])
	_propose_savings(wanted, demand)
	for pick: Array in wanted:
		var s: Actor = pick[0]
		var type: StringName = pick[1]
		# A structure that can't train any combat unit (e.g. the Settlement, which only
		# makes the weaponless Stock Truck) instead fields a capped number of utility
		# units — builders/capturers that earn their keep outside the army.
		if type == &"":
			type = _best_utility_unit_for(s)
		# Train the wanted unit only when we can afford it AND paying for it leaves the reserve
		# banked; otherwise wait and bank energy for it instead of falling back to something
		# cheaper and less useful. The reserve is checked HERE, at the one place this manager
		# spends, rather than inside each "what do I want" helper: what the bot wants does not
		# depend on the floor, only whether it may buy it now does.
		if type != &"" and _can_afford_above_reserve(type):
			_act.train(s, type)
			_bot.savings.spent(type)
	return DEMAND_WORK_UNITS + producers.size() * PRODUCER_WORK_UNITS


## Production's savings proposal: the most valuable unit any idle producer wants, affordable
## or not, on the scale every proposal shares (Bot.unit_composition_value). See BotSavings.
func _propose_savings(a_wanted: Array, a_demand: Dictionary) -> void:
	var types: Array = []
	for pick: Array in a_wanted:
		if pick[1] != &"" and not types.has(pick[1]):
			types.append(pick[1])
	if types.is_empty():
		_bot.savings.propose(&"production", &"", 0.0, 0)
		return
	# ON THE ONE PURCHASE SCALE (Bot.purchase_values_per_energy), the same the economy prices its
	# proposals on. Until 2026-10-10 this read unit_composition_value — the demand map's scale,
	# values near 1–7 — while the economy's proposal was the learned model's marginal per energy,
	# near 0.001, so production's unit won the savings goal in every think of every match, no
	# dear purchase was ever banked for, and the tech rung's margin test — which the Constable
	# cleared — never mattered: the bank never held 1,200. Found by a probe of _best_tech in a
	# ten-minute game (bot-architecture.md §The tech rung).
	var valued: Dictionary = _bot.purchase_values_per_energy(types, a_demand)["values"]
	var best_type: StringName = &""
	var best_value: float = 0.0
	for type: StringName in types:
		var value: float = float(valued[type])
		if value > best_value:
			best_value = value
			best_type = type
	_bot.savings.propose(&"production", best_type, best_value, _energy_cost(best_type))


## THE INFRASTRUCTURE RUNG, for a faction whose provider is a TRAINED unit (the Technocratic
## Surveyor; Bot.infrastructure_source_is_unit). While the bot is strained and none is already
## on its way, the first idle producer that can make one trains it ahead of anything else.
## Returns that producer, or null when nothing was ordered.
##
## The economy's infrastructure rung is the structure half of this and banks while it waits
## (BotEconomy._decide). Like that rung, this one is EXEMPT from the reserve: infrastructure is a
## purchase the bank exists to keep affordable. A provider is not a combat or utility unit, so
## without this the bot never trained one — and the economy, finding no structure provider,
## would have built Outposts for infrastructure instead.
func _train_infrastructure_unit(a_idle_producers: Array) -> Actor:
	if not _bot.needs_infrastructure_provider() or not _bot.infrastructure_source_is_unit():
		return null
	var source: StringName = _bot.infrastructure_source_type()
	if _infrastructure_unit_on_its_way(source) or not _bot.can_afford(source):
		return null
	for s: Actor in a_idle_producers:
		if s.production.can_produce(source):
			_act.train(s, source)
			return s
	return null


## Whether an infrastructure unit of `a_type` is already queued or training: strain does not
## lift until it is out and standing, so without this every think orders another.
func _infrastructure_unit_on_its_way(a_type: StringName) -> bool:
	for t: PurchaseTransaction in _bot.production_queue.pending():
		if t.type == a_type and t.is_pending():
			return true
	for s: Actor in _bot.get_production_structures():
		if s.production.is_producing(a_type):
			return true
	return false


## Cheapest affordable producible utility unit at [structure] that the bot still has WORK
## for, or UNDEFINED. Used only when no combat unit is producible there.
func _best_utility_unit_for(a_structure: Actor) -> StringName:
	var best: StringName = &""
	var best_cost: int = 1 << 30
	for t: StringName in _bot.considered_producible_types(a_structure.production):
		if not _bot.unit_is_utility(t):
			continue
		if _bot.get_units_of_type(t).size() >= _utility_demand_for(t):
			continue
		if not _bot.can_afford(t):
			continue
		var cost: int = _energy_cost(t)
		if cost < best_cost:
			best_cost = cost
			best = t
	return best


## HOW MANY UNITS OF UTILITY TYPE [type] THE BOT HAS LIVE ERRANDS FOR.
##
## THE COUNT FOLLOWS THE WORK, which is the whole point: every other purchase this module
## makes is a comparison (unit_composition_value — effectiveness × demand, with cost
## explicitly not a tiebreaker), and utility units were the one purchase still decided by a
## constant. A utility unit with no errand is the definition of "too many", and every input
## needed to say what the errands are already existed.
##
## The terms, each one an errand somebody has to be there to do:
##
##   BUILDING — one builder per concurrent build job. `build_concurrency` is exactly how many
##     jobs the bot will run at once, so it is exactly how many builders it wants; below that
##     BotEconomy pulls a fighter off the line to make up the difference.
##   CAPTURING — one carrier per capturable CLUSTER (Bot.capturable_clusters), and only while
##     the bot owns somewhere to bank prisoners, which is the same gate
##     BotOpportunist._gather_captures applies before it will send anyone. No camp, no
##     errand. A cluster rather than a body because a truck holding three collects a knot of
##     infantry in one trip.
##   THE SPARE — UTILITY_SPARE, one over the visible work. See there.
##
## Two corrections for things that changed after the question was asked, both of which make
## a naive demand model UNDER-build:
##
##   SCOUTING IS AN ERRAND TOO, and since the ATTACK objective became fog-limited it is the
##     errand the whole offensive waits on. It belongs to the POOL rather than to a type —
##     any spare body can take it — so it raises this type's allowance by one only while the
##     pool as a whole is short of the scout budget, instead of being counted once per type.
##   A CRUSHER IS ARMY AS WELL AS ERRAND. BotMilitary._combat_units claims anything with
##     combat utility, so a Stock Truck sitting between capture errands is in the attack
##     wave rather than standing idle. An extra one is therefore not waste, and a model that
##     priced it as pure overhead would starve the very pool the military draws from.
##
## Bounded above by `utility_unit_cap`, which is now a ceiling on the answer rather than the
## answer itself.
func _utility_demand_for(a_type: StringName) -> int:
	var demand: int = UTILITY_SPARE
	if _bot.unit_type_can_build(a_type):
		# One builder per concurrent job. UNCAPPED concurrency has no finite job count to ask
		# for, so it wants as many builders as it is allowed to own — the mini() below against
		# `utility_unit_cap` is what actually bounds the answer either way.
		demand += (
			utility_unit_cap
			if BotDifficulty.is_build_uncapped(build_concurrency)
			else BotDifficulty.build_slots(build_concurrency)
		)
	if _bot.unit_type_can_capture(a_type):
		demand += _capture_errand_count()
	if _bot.unit_type_has_combat_utility(a_type):
		demand += 1
	# SYNERGY PIECES (Alex, 2026-10-10 — bot-architecture.md §The siege rung): a transport while a
	# squad has a lift worth taking and the bot owns none to take it (BotEscort sets the flag);
	# a mobile spotter while the bot owns a siege gun and nothing that can carry a solution to
	# a target. Each is one errand, so each is one unit — the same rule as a carrier per capture.
	if _bot.unit_type_is_transport(a_type) and _bot.lift_wanted:
		demand += 1
	if _bot.unit_type_is_mobile_spotter(a_type) and _spotter_wanted():
		demand += 1
	if _owned_utility_unit_count() < scout_unit_budget:
		demand += 1
	return mini(demand, maxi(0, utility_unit_cap))


## Whether a mobile spotter is wanted: the bot owns a finished siege gun and no unit that can
## carry spotting to a target.
func _spotter_wanted() -> bool:
	var owns_gun: bool = _bot.get_structures().any(
		func(s: Actor) -> bool: return s.is_built and Relation.grants_command(s, "command_bombard")
	)
	return owns_gun and not _bot.get_units().any(Bot.is_mobile_spotter)


## Live capture errands: capturable clusters, but zero while the bot owns nowhere to deposit
## prisoners — a carrier with no camp cannot complete the loop and the opportunist will not
## dispatch one. Cached for the tick (see _capture_errands).
func _capture_errand_count() -> int:
	if _capture_errands < 0:
		_capture_errands = (
			0 if _bot.get_deposit_structures().is_empty() else _bot.capturable_clusters().size()
		)
	return _capture_errands


## Every owned unit whose TYPE is a utility type — the pool the scout, the builder and the
## carrier are all drawn from. Counted across types because scouting is a pool errand.
func _owned_utility_unit_count() -> int:
	var count: int = 0
	for u: Actor in _bot.get_units():
		if _bot.unit_is_utility(u.id):
			count += 1
	return count


## The producible unit at [structure] that best counters the believed enemy. With no
## intel yet (empty demand), falls back to the cheapest affordable unit so the
## building still fields an opening army.
func _best_unit_for(a_structure: Actor, a_demand: Dictionary) -> StringName:
	if a_demand.is_empty():
		return _cheapest_affordable_unit(a_structure)
	var types: Array = []
	for t: StringName in _bot.considered_producible_types(a_structure.production):
		# Only train combat units — a weaponless unit (e.g. the Stock Truck) adds
		# nothing to the army, so a structure that can ONLY make such units waits
		# rather than spamming them. Builders are fielded via the economy, not here.
		if not _bot.unit_can_attack(t):
			continue
		# Only units the bot can TRAIN TODAY. A tech-locked unit scores on its gun like any
		# other, wins the comparison, and then fails the spend gate every tick — and the caller
		# banks for it rather than falling back, so the producer stands idle on a unit the bot
		# has no building for. Measured 2026-10-04 (piece-usage audit): the Constable was picked
		# 46,707 of 56,794 barracks decisions and the Avalanche 9,247 of 10,212 war-factory
		# decisions, neither ever trained, while the bot owned no tech structure.
		if not _bot.has_tech_for(t):
			continue
		types.append(t)
	# The one valuation every purchase reads (Bot.purchase_values_per_energy): the model's
	# marginal per energy where it applies, else the demand map.
	var valued: Dictionary = _bot.purchase_values_per_energy(types, a_demand)
	var scores: Array = types.map(func(t: StringName) -> float: return float(valued["values"][t]))
	# A draw at the bot's temperature rather than the argmax, so two matches do not field the
	# same mix; with no generator or at 0 it IS the argmax.
	var chosen: int = BotSampling.pick(scores, decision_temperature, rng)
	var picked: StringName = types[chosen] if chosen >= 0 else &""
	var scored: Dictionary = {}
	for i: int in types.size():
		scored[types[i]] = scores[i]
	_act.usage.record_choice("train_learned" if valued["learned"] else "train", scored, picked)
	return picked


func _cheapest_affordable_unit(a_structure: Actor) -> StringName:
	var best: StringName = &""
	var best_cost: int = 1 << 30
	var scored: Dictionary = {}  # cheaper scores higher, so the audit reads it like any choice
	for t: StringName in _bot.considered_producible_types(a_structure.production):
		# Same combat-only gate as _best_unit_for: never mass a non-combat unit as
		# the "opening army" filler.
		if not _bot.unit_can_attack(t):
			continue
		if _bot.can_afford(t):
			var cost: int = _energy_cost(t)
			scored[t] = -cost
			if cost < best_cost:
				best_cost = cost
				best = t
	_act.usage.record_choice("train_opening", scored, best)
	return best


## Affordable, and still leaves `reserve` banked afterwards — the training half of the
## commander-wide spending floor. See BotEconomy.can_afford_above_reserve.
func _can_afford_above_reserve(a_type) -> bool:
	return (
		_bot.can_afford(a_type)
		and _bot.energy - _energy_cost(a_type) >= reserve + _bot.savings.claim_against(a_type)
	)


func _energy_cost(a_type) -> int:
	var spec: TechnologySpec = _bot.technology_mapping.get(a_type)
	return spec.energy_cost if spec != null else 0
