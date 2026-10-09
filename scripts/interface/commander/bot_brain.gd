class_name BotBrain
extends Node

## BotBrain — the decision + tick layer for a CPU-controlled commander.
##
## Architecture (perception → decision → action):
##   • Perception lives on the [Bot] this node is a child of (bot.gd — read-only
##     "senses": economy, army, threat, spatial, tech, phase).
##   • Decision lives HERE: the strategy managers, each run as one or more BotJobs on its own
##     period by the session's shared BotScheduler (see register_jobs), and the BotClaims
##     registry that says which manager owns which unit.
##   • Action will live in a thin actuator layer (the only place that issues
##     commands), kept separate so the decision code stays pure and testable.
##
## One BotBrain is attached per non-neutral commander by Scenario._attach_brain(), which
## sets [difficulty] from the commander's PlayerSlot and switches it off for a human slot.
## The neutral commander (id 0) never gets one.

## This bot's difficulty, propagated from its PlayerSlot. Write it through
## `set_difficulty` — the tier only matters through the [config] it selects.
var difficulty: PlayerSlot.Difficulty = PlayerSlot.Difficulty.MEDIUM

## THE PARAMETERS THIS BOT PLAYS BY. Every handicap lives here rather than in a branch on
## `difficulty`, so a tier is a set of numbers that can be searched — see BotDifficulty.
var config: BotDifficulty = BotDifficulty.for_tier(PlayerSlot.Difficulty.MEDIUM)

## When false the think loop is skipped entirely: the bot is inert. A human slot's brain is
## off; Scenario.set_ai_control is what switches one on or off mid-match.
##
## NOT what PASSIVE means any more. A passive bot is "minimally active, and never attacks",
## which is a bot that still thinks — it builds, trains and defends itself, and
## `config.may_attack` is what stops it marching. Leaving it inert made it scenery rather
## than an opponent. This flag survives for a scenario that genuinely wants a frozen
## commander.
var active: bool = true

## Seconds between preservation sweeps. A retreat decision, so about as quick as a player
## glancing at a losing fight — but not a difficulty knob: noticing a unit about to die is not
## a handicap the tiers vary.
const PRESERVATION_PERIOD_SECONDS: float = 1.0

## Which of several jobs due on the same tick runs first (BotJob.priority). Combat first, so a
## tick short of budget delays scouting rather than a fight; momentum before everything,
## because the military reads it.
## Above everything: until the command centre is down the bot has no economy to run.
## Perception before any decision that reads it: the fields are rebuilt before the managers
## on the same tick look at them.
const JOB_PRIORITY_FIELDS: int = 110
const JOB_PRIORITY_DEPLOYMENT: int = 100
const JOB_PRIORITY_MOMENTUM: int = 90
const JOB_PRIORITY_TARGETING: int = 80
const JOB_PRIORITY_MILITARY: int = 70
const JOB_PRIORITY_KAMIKAZE: int = 60
const JOB_PRIORITY_PRESERVATION: int = 60
const JOB_PRIORITY_SANCTION: int = 50
## Beside the sanctions: a local ability is a cast too, aimed at what targeting just engaged.
const JOB_PRIORITY_ABILITIES: int = 50
const JOB_PRIORITY_OPPORTUNIST: int = 40
const JOB_PRIORITY_ECONOMY: int = 30
const JOB_PRIORITY_PRODUCTION: int = 20
## After production: an upgrade is a purchase priced on the army production has fielded.
const JOB_PRIORITY_RESEARCH: int = 15
const JOB_PRIORITY_SCOUT: int = 10

## Work units a job reports when it did nothing measurable, so a no-op still counts against
## the budget rather than looking free.
const IDLE_JOB_WORK_UNITS: int = 1
## Work units per unit the preservation sweep looks at (BotScheduler counts work in units of
## roughly a microsecond on the calibration machine).
const PRESERVATION_UNIT_WORK_UNITS: int = 2

## HP fraction at or below which a unit is considered "at risk" for preservation.
const PRESERVATION_HP_THRESHOLD: float = 0.25

## The Bot (a Commander subclass carrying the perception API) this brain drives.
var bot: Bot

## Strategy layer — built lazily on the first think() once the Bot's map is
## resolved. The actuator is the shared command-issuing surface; the managers
## decide and call into it.
var _actuator: BotActuator
## Whether the bot is winning or losing — sampled first each think, read by the military.
var _momentum: BotMomentum
var _economy: BotEconomy
var _deployment: BotDeployment
var _military: BotMilitary
var _abilities: BotAbilities
var _research: BotResearch
var _production: BotProduction
var _targeting: BotTargeting
var _kamikaze: BotKamikaze
var _sanction: BotSanction
var _scout: BotScout
## Opportunistic, utility-driven decisions (e.g. Warlords liberating Shelters for free
## units). Extensible: new utility decisions register as gatherers inside it.
var _opportunist: BotOpportunist

## Which manager owns which unit — shared by every manager of this bot.
var claims: BotClaims = BotClaims.new()

## THE BOT'S OWN GENERATOR, seeded from the match seed and the slot (seed_randomness), so a
## match is reproducible from its seed and two bots never share a stream — a shared stream
## drawn in interleaved order would make each bot's draws depend on the other's think order.
## Null until seeded: a brain nobody seeded (a bare one in a test) draws nothing, and every
## scored decision stays the argmax it was. See gdd/systems/ai/bot-randomness.md.
var rng: RandomNumberGenerator = null
## Keeps the bot's stream apart from the simulation's and the global one, which are seeded
## from the same number.
const BOT_STREAM_SALT: int = 0x5EEDB07
## Spreads consecutive commander ids across the seed space; a prime, so no two slots' salts
## collide with a small match seed's low bits.
const SLOT_SALT_STRIDE: int = 7919
## The personality is drawn ONCE, on the first think, so overrides pushed before it (a
## harness pinning spread to 0) are part of what is drawn from.
var _personality_drawn: bool = false

## This brain's jobs, in the order `think` runs them. Built with the managers.
var _jobs: Array[BotJob] = []
## Every job a brain runs, by name — what `PlayerSlot.disabled_bot_jobs` may name.
## `tests/test_BotJobSwitches.gd` holds it to the jobs `_build_jobs` actually makes.
const JOB_NAMES: Array[StringName] = [
	&"fields",
	&"deployment",
	&"momentum",
	&"targeting",
	&"military",
	&"sanction",
	&"abilities",
	&"kamikaze",
	&"preservation",
	&"opportunist",
	&"economy",
	&"production",
	&"research",
	&"scout_sight",
	&"scout",
]
## Jobs this brain leaves off: a mission running the economy and production while it authors
## the military itself (gdd/systems/ai/squads-and-relations.md §Squads). Set before the jobs
## are registered; empty runs them all.
var disabled_jobs: Array[StringName] = []
## Whether the jobs have been handed to the session's scheduler.
var _registered: bool = false


## Set the tier and the parameters it selects together, so the two can never disagree.
func set_difficulty(a_tier: PlayerSlot.Difficulty) -> void:
	difficulty = a_tier
	config = BotDifficulty.for_tier(a_tier)
	# Mid-match, the managers already hold the old tier's numbers.
	if _military != null:
		_apply_config()


## Replace the parameters this bot plays by, WITHOUT touching the tier it reports.
##
## The injection point for a tuning run: the search wants to try values the tier table does
## not contain, and the alternative — editing `BotDifficulty.for_tier` per experiment — would
## make the tiers a property of the build rather than of the game, so two parameter sets
## could not be run side by side and no result would name what produced it. See
## tools/selfplay/ and gdd/systems/ai/selfplay-harness.md.
##
## `difficulty` deliberately keeps its old value: it is the tier this bot IS (what a scenario
## authored, what a HUD would show), while `config` is what it plays by. A search that
## rewrote the tier would be reporting a lie about the second one.
##
## Re-applies to the managers when they already exist, so this works mid-match as well as at
## attach time.
func set_config(a_config: BotDifficulty) -> void:
	if a_config == null:
		return
	config = a_config
	if _military != null:
		_apply_config()


## Give this brain its own seeded stream. Called by Scenario._attach_brain with the match seed
## and the commander id; a test seeds whatever it likes. Re-seeding re-arms the personality
## draw, so a brain re-seeded before its first think draws from the new stream.
func seed_randomness(a_match_seed: int, a_slot_salt: int) -> void:
	rng = RandomNumberGenerator.new()
	rng.seed = a_match_seed ^ (a_slot_salt * SLOT_SALT_STRIDE) ^ BOT_STREAM_SALT
	_personality_drawn = false


## The per-match personality: `config` jittered by its own spread, once. A brain with no
## generator keeps the tier exactly.
func _draw_personality() -> void:
	if rng == null or _personality_drawn:
		return
	_personality_drawn = true
	config = config.jittered(rng, config.personality_spread)


func _ready() -> void:
	bot = get_parent() as Bot
	if bot == null:
		push_warning("BotBrain expects to be a child of a Bot; found %s" % get_parent())


## Polls only until the strategy layer can be built (Bot._ready resolves the map), then hands
## the jobs to the scheduler and stops: from then on the scheduler is what runs this brain.
func _physics_process(_a_delta: float) -> void:
	if bot == null or Engine.is_editor_hint():
		return
	if not _ensure_managers():
		return
	# Hosted beside the commanders, so it lives and pauses with the session they belong to.
	var host: Node = bot.get_parent() if bot.get_parent() != null else bot
	register_jobs(BotScheduler.find_or_create(self, host))
	set_physics_process(false)


## Hand this brain's jobs to `a_scheduler`. Once only.
func register_jobs(a_scheduler: BotScheduler) -> void:
	if _registered or not _ensure_managers():
		return
	_registered = true
	for job: BotJob in enabled_jobs():
		a_scheduler.register(job)


## Run every job once, to completion, in scheduling order — a whole decision pass in one call,
## outside the scheduler. For tests and probes; the game itself is paced by BotScheduler.
func think() -> void:
	if not _ensure_managers():
		return
	for job: BotJob in enabled_jobs():
		job.work.call(BotScheduler.WORK_UNITS_PER_TICK)
		while job.has_pending_work():
			job.work.call(BotScheduler.WORK_UNITS_PER_TICK)


## The jobs this brain runs: every one it built, less those its slot switched off.
func enabled_jobs() -> Array[BotJob]:
	return _jobs.filter(func(job: BotJob) -> bool: return not disabled_jobs.has(job.name))


## This brain's jobs, built with the managers. The periods are read through the config on
## every run, so a set_config mid-match re-paces them.
func _build_jobs() -> void:
	var combat: Callable = func() -> float: return config.combat_period_seconds
	var strategy: Callable = func() -> float: return config.strategy_period_seconds
	var scouting: Callable = func() -> float: return config.scout_period_seconds
	var fields: Callable = func() -> float: return config.field_refresh_seconds
	_jobs = [
		# The spatial fields: a rebuild begun each period and carried on in pieces until it is
		# complete (BotFields.advance), so no tick pays for every sweep at once.
		BotJob.new(&"fields", self, fields, JOB_PRIORITY_FIELDS, _tick_fields, _fields_pending),
		BotJob.new(
			&"deployment",
			self,
			strategy,
			JOB_PRIORITY_DEPLOYMENT,
			_deployment.tick,
			_deployment.is_pending
		),
		BotJob.new(&"momentum", self, combat, JOB_PRIORITY_MOMENTUM, _unit_work(_momentum.tick)),
		BotJob.new(&"targeting", self, combat, JOB_PRIORITY_TARGETING, _unit_work(_targeting.tick)),
		BotJob.new(&"military", self, combat, JOB_PRIORITY_MILITARY, _unit_work(_military.tick)),
		BotJob.new(&"sanction", self, combat, JOB_PRIORITY_SANCTION, _unit_work(_sanction.tick)),
		BotJob.new(&"abilities", self, combat, JOB_PRIORITY_ABILITIES, _unit_work(_abilities.tick)),
		BotJob.new(
			&"kamikaze",
			self,
			func() -> float: return BotKamikaze.EVAL_PERIOD_SECONDS,
			JOB_PRIORITY_KAMIKAZE,
			_unit_work(_kamikaze.tick)
		),
		BotJob.new(
			&"preservation",
			self,
			func() -> float: return PRESERVATION_PERIOD_SECONDS,
			JOB_PRIORITY_PRESERVATION,
			_unit_work(_tick_preservation)
		),
		BotJob.new(
			&"opportunist", self, strategy, JOB_PRIORITY_OPPORTUNIST, _unit_work(_opportunist.tick)
		),
		BotJob.new(
			&"economy",
			self,
			strategy,
			JOB_PRIORITY_ECONOMY,
			_economy.tick,
			_economy.has_pending_search
		),
		BotJob.new(
			&"production", self, strategy, JOB_PRIORITY_PRODUCTION, _unit_work(_production.tick)
		),
		BotJob.new(&"research", self, strategy, JOB_PRIORITY_RESEARCH, _unit_work(_research.tick)),
		# Seeing comes before dispatching, so a scout is sent on from what was just seen.
		BotJob.new(
			&"scout_sight",
			self,
			scouting,
			JOB_PRIORITY_SCOUT + 1,
			_scout.sweep_sight,
			_scout.is_sight_pending
		),
		BotJob.new(
			&"scout", self, scouting, JOB_PRIORITY_SCOUT, _scout.tick, _scout.is_dispatch_pending
		),
	]


## The fields job's work: begin a rebuild when none is pending, then carry it on within the
## allowance. A bot with no map has no fields and the job idles.
func _tick_fields(a_allowance: int) -> int:
	var fields: BotFields = bot.fields()
	if fields == null:
		return IDLE_JOB_WORK_UNITS
	if not fields.is_pending():
		fields.refresh()
	return maxi(IDLE_JOB_WORK_UNITS, fields.advance(a_allowance))


func _fields_pending() -> bool:
	var fields: BotFields = bot.fields()
	return fields != null and fields.is_pending()


## Wrap a manager's `tick() -> int` (work units spent) as a job's work callable. The allowance
## is not passed down: these ticks always finish, and report what they cost. (The economy's and
## the scout's ticks take the allowance themselves, and are registered unwrapped.)
static func _unit_work(tick: Callable) -> Callable:
	return func(_allowance: int) -> int: return maxi(IDLE_JOB_WORK_UNITS, int(tick.call()))


## Push the difficulty parameters into the managers that read them. Called once the layer is
## built; re-callable, so a scenario that changes a bot's tier mid-match need only call it.
func _apply_config() -> void:
	if config == null:
		return
	_military.army_commit_threshold = config.army_commit_threshold
	_military.may_attack = config.may_attack
	_military.attack_value_ratio = config.attack_value_ratio
	_military.assumed_enemy_parity = config.assumed_enemy_parity
	_military.wave_abort_fraction = config.wave_abort_fraction
	_military.reinforce_fraction = config.reinforce_fraction
	_military.squad_cap = config.squad_cap
	_military.guard_strength_ratio = config.guard_strength_ratio
	_military.defend_threat_radius = config.defend_threat_radius
	_targeting.switch_margin = config.retarget_switch_margin
	_targeting.set_signal_weights(
		config.retarget_weight_effectiveness,
		config.retarget_weight_finishability,
		config.retarget_weight_proximity
	)
	_scout.unit_budget = config.scout_unit_budget
	_economy.reserve = config.economy_reserve
	_economy.build_concurrency = config.build_concurrency
	_economy.production_structure_cap = config.production_structure_cap
	_economy.income_structure_target = config.income_structure_target
	_economy.defence_propensity = config.defence_propensity
	_economy.tech_value_margin = config.tech_value_margin
	# The research rung buys on the same margin the tech rung buys a building on, and banks
	# the same reserve every other spender does.
	_research.tech_value_margin = config.tech_value_margin
	_research.reserve = config.economy_reserve
	# The economy is the THIRD consumer of the threat radius (BotMilitary and BotSanction are
	# the others). "Is something of mine under attack" has to mean one thing across the bot,
	# and it is what tells the economy to stop expanding — see BotEconomy.safety.
	_economy.defend_threat_radius = config.defend_threat_radius
	# Where a building goes, as three costs per cell against compactness = 1.0. See
	# BotEconomy §WHERE A BUILDING GOES for why compactness itself is not a parameter.
	_economy.place_frontage_bias = config.place_frontage_bias
	_economy.place_shelter_bias = config.place_shelter_bias
	_economy.place_corridor_weight = config.place_corridor_weight
	_economy.place_coverage_weight = config.place_coverage_weight
	_production.utility_unit_cap = config.utility_unit_cap
	# The two errand counts the utility demand is sized against. Both are already parameters
	# of other managers; production reads them because a builder and a scout are units it has
	# to have MADE. See BotProduction._utility_demand_for.
	_production.build_concurrency = config.build_concurrency
	_production.scout_unit_budget = config.scout_unit_budget
	# The same reserve the economy plays by: it is a COMMANDER-WIDE spending floor, and a
	# floor one of the two spenders ignores is not a floor (see BotProduction.reserve).
	_production.reserve = config.economy_reserve
	_sanction.may_attack = config.may_attack
	_sanction.defend_threat_radius = config.defend_threat_radius
	# The three scored modules sample at one temperature; placement is deliberately not one
	# of them (it must stay mirror-exact — BotEconomy §WHERE A BUILDING GOES).
	_production.decision_temperature = config.decision_temperature
	_production.should_use_learned_production = config.should_use_learned_production
	_opportunist.decision_temperature = config.decision_temperature
	_scout.decision_temperature = config.decision_temperature
	# The two production-mix weights live on the PERCEPTION layer (Bot.enemy_demand_map is
	# what reads them), so they are pushed onto the bot rather than onto a manager. Same
	# discipline either way: a number handed down, never a branch on the tier.
	if bot != null:
		bot.structure_demand_weight = config.structure_demand_weight
		bot.demand_coverage_falloff = config.demand_coverage_falloff
		bot.arrival_margin_falloff_seconds = config.arrival_margin_falloff_seconds
		bot.use_fields = config.should_use_fields


## The momentum signal, or null before the strategy layer is built (first think). Lets a
## scenario / debugger read whether the bot believes it is losing.
func get_momentum() -> BotMomentum:
	return _momentum


## The scout manager, or null before the strategy layer is built (first think). Lets a
## scenario / debugger read scouting coverage (BotScout.observed_fraction).
func get_scout() -> BotScout:
	return _scout


## The military manager, or null before the strategy layer is built. Read by a decision
## simulation for the posture and the objective (gdd/systems/ai/decision-sims.md); nothing
## outside the brain decides through it.
func get_military() -> BotMilitary:
	return _military


## The economy manager, or null before the strategy layer is built. Read by the debug overlay
## (gdd/systems/ai/debug-signals.md); nothing outside the brain decides through it.
func get_economy() -> BotEconomy:
	return _economy


## The targeting manager, or null before the strategy layer is built. Read by the debug overlay.
func get_targeting() -> BotTargeting:
	return _targeting


## The actuator, or null before the strategy layer is built. Read by the self-play harness
## for its usage ledger (BotActuator.usage); nothing outside the brain issues through it.
func get_actuator() -> BotActuator:
	return _actuator


## Build the strategy layer once the Bot's map is available (Bot._ready resolves
## it from the scenario). Returns false until then so think() no-ops safely.
func _ensure_managers() -> bool:
	if _military != null:
		return true
	if bot == null or bot.map == null:
		return false
	_actuator = BotActuator.new(bot.map)
	_momentum = BotMomentum.new(bot)
	# The economy takes momentum for the same reason the military does: whether the bot is
	# bleeding right now is half of "is it safe to go and take an extractor".
	_economy = BotEconomy.new(bot, _actuator, _momentum)
	# Ranks its drop spots with the economy's placement score, so the bot has one notion of a
	# good spot for a building however the building arrives.
	_deployment = BotDeployment.new(bot, _economy)
	_production = BotProduction.new(bot, _actuator)
	_military = BotMilitary.new(bot, _actuator, _momentum)
	_targeting = BotTargeting.new(bot, _actuator)
	_kamikaze = BotKamikaze.new(bot, _actuator)
	# BotSanction needs no event host handed to it: it issues UseSanction like the player,
	# and the command resolves the host itself.
	_sanction = BotSanction.new(bot, _actuator)
	_scout = BotScout.new(bot, _actuator)
	# A REVEAL sanction is aimed by what the scout has not seen, and stamps what it shows.
	_sanction.scout = _scout
	_opportunist = BotOpportunist.new(bot, _actuator)
	_abilities = BotAbilities.new(bot, _actuator)
	_research = BotResearch.new(bot, _actuator)
	# One registry, shared: a claim means nothing unless every manager reads the same one.
	for manager: Object in [
		_economy, _military, _targeting, _kamikaze, _scout, _opportunist, _abilities
	]:
		manager.set("claims", claims)
	# One stream, shared by the modules that sample (null stays null: they then argmax).
	for manager: Object in [_production, _opportunist, _scout]:
		manager.set("rng", rng)
	# The personality is drawn BEFORE the config is pushed, so what the managers play by is
	# this match's draw and not the tier.
	_draw_personality()
	# AFTER every manager exists, and after construction rather than through their
	# constructors: a manager that ignores difficulty should not have to take it, and one that
	# starts reading it should not change its own call site.
	_apply_config()
	_build_jobs()
	return true


# ─── UNIT PRESERVATION ──────────────────────────────────────────────────────


## Whether this bot should attempt to save [unit] from destruction — a PARAMETER now
## (`BotDifficulty.preserve_min_cost`) rather than a match on the tier, so the threshold is
## a number a tuning run can move rather than three branches it cannot.
func _should_preserve(a_unit: Actor) -> bool:
	if config == null:
		return false
	var spec: TechnologySpec = bot.technology_mapping.get(a_unit.id)
	return config.preserves_unit_costing(spec.energy_cost if spec != null else 0)


## Run every PRESERVATION_PERIOD_SECONDS. For each owned unit that _should_preserve
## AND is at-risk (hp ≤ PRESERVATION_HP_THRESHOLD) AND has no effective targets in
## aggro range AND is actively fighting (Attack or AttackMove command), cancel the
## fight and move the unit home. Returns the work units spent: one per unit looked at.
func _tick_preservation() -> int:
	if _actuator == null:
		return 0
	var units: Array = bot.get_units()
	for unit: Actor in units:
		if not _should_preserve(unit):
			continue
		if unit.defense == null:
			continue
		if unit.defense.hp / unit.defense.hp_max > PRESERVATION_HP_THRESHOLD:
			continue
		if not _no_effective_targets_in_aggro(unit):
			continue
		var cmd: MoveCommand = unit.current_command()
		if not (cmd is Attack or cmd is AttackMove):
			continue
		unit.update_commands(null)
		var garrison_host: Actor = bot.nearest_garrison_for(unit)
		if garrison_host != null:
			_actuator.garrison_into(unit, garrison_host)
		else:
			_actuator.move([unit], _preservation_retreat_dest(unit))
	return units.size() * PRESERVATION_UNIT_WORK_UNITS


## True when the unit has enemies in its aggro range but cannot effectively damage
## any of them (unit_effectiveness_vs returns 0 for every target). Returns false
## — i.e. "don't retreat on this gate" — when the range is empty, since an
## attack-moving unit with no enemies nearby isn't in a bad matchup yet.
func _no_effective_targets_in_aggro(a_unit: Actor) -> bool:
	var nearby: Array = bot.get_enemies_in_aggro_range(a_unit)
	if nearby.is_empty():
		return false
	for enemy: Actor in nearby:
		if bot.unit_effectiveness_vs(a_unit.id, enemy) > 0.0:
			return false
	return true


## Retreat destination for [unit]: nearest own structure, or base centroid as
## fallback when the bot has no structures left.
func _preservation_retreat_dest(a_unit: Actor) -> Vector3:
	var nearest: Actor = bot.nearest_own_structure(a_unit.global_position)
	if nearest != null:
		return nearest.global_position
	return bot.base_centroid()
