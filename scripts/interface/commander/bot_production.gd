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
	for s: Commandable in producers:
		var type: StringName = _best_unit_for(s, demand)
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
	return DEMAND_WORK_UNITS + producers.size() * PRODUCER_WORK_UNITS


## Cheapest affordable producible utility unit at [structure] that the bot still has WORK
## for, or UNDEFINED. Used only when no combat unit is producible there.
func _best_utility_unit_for(a_structure: Commandable) -> StringName:
	var best: StringName = &""
	var best_cost: int = 1 << 30
	for t: StringName in a_structure.production.producible_types:
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
	if _owned_utility_unit_count() < scout_unit_budget:
		demand += 1
	return mini(demand, maxi(0, utility_unit_cap))


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
	for u: Commandable in _bot.get_units():
		if _bot.unit_is_utility(u.id):
			count += 1
	return count


## The producible unit at [structure] that best counters the believed enemy. With no
## intel yet (empty demand), falls back to the cheapest affordable unit so the
## building still fields an opening army.
func _best_unit_for(a_structure: Commandable, a_demand: Dictionary) -> StringName:
	if a_demand.is_empty():
		return _cheapest_affordable_unit(a_structure)
	var types: Array = []
	var scores: Array = []
	for t: StringName in a_structure.production.producible_types:
		# Only train combat units — a weaponless unit (e.g. the Stock Truck) adds
		# nothing to the army, so a structure that can ONLY make such units waits
		# rather than spamming them. Builders are fielded via the economy, not here.
		if not _bot.unit_can_attack(t):
			continue
		types.append(t)
		scores.append(_bot.unit_composition_value(t, a_demand))
	# A draw at the bot's temperature rather than the argmax, so two matches do not field the
	# same mix; with no generator or at 0 it IS the argmax.
	var chosen: int = BotSampling.pick(scores, decision_temperature, rng)
	return types[chosen] if chosen >= 0 else &""


func _cheapest_affordable_unit(a_structure: Commandable) -> StringName:
	var best: StringName = &""
	var best_cost: int = 1 << 30
	for t: StringName in a_structure.production.producible_types:
		# Same combat-only gate as _best_unit_for: never mass a non-combat unit as
		# the "opening army" filler.
		if not _bot.unit_can_attack(t):
			continue
		if _bot.can_afford(t):
			var cost: int = _energy_cost(t)
			if cost < best_cost:
				best_cost = cost
				best = t
	return best


## Affordable, and still leaves `reserve` banked afterwards — the training half of the
## commander-wide spending floor. See BotEconomy.can_afford_above_reserve.
func _can_afford_above_reserve(a_type) -> bool:
	return _bot.can_afford(a_type) and _bot.energy - _energy_cost(a_type) >= reserve


func _energy_cost(a_type) -> int:
	var spec: TechnologySpec = _bot.technology_mapping.get(a_type)
	return spec.energy_cost if spec != null else 0
