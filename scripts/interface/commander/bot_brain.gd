class_name BotBrain
extends Node

## BotBrain — the decision + tick layer for a CPU-controlled commander.
##
## Architecture (perception → decision → action):
##   • Perception lives on the [Bot] this node is a child of (bot.gd — read-only
##     "senses": economy, army, threat, spatial, tech, phase).
##   • Decision lives HERE: a throttled think() pass that will host the strategy
##     managers (economy / production / military) coordinated by a posture FSM.
##   • Action will live in a thin actuator layer (the only place that issues
##     commands), kept separate so the decision code stays pure and testable.
##
## One BotBrain is attached per non-human, non-neutral commander by
## Scenario._attach_brain(), which sets [difficulty] (and derives [active]) from the
## commander's PlayerSlot. A neutral (id 0) or human-controlled commander never gets
## one.

## This bot's difficulty, propagated from its PlayerSlot. Stored for future tuning;
## for now only PASSIVE changes behaviour (it leaves [active] false → the bot is
## inert), and every other tier behaves identically.
var difficulty: PlayerSlot.Difficulty = PlayerSlot.Difficulty.MEDIUM

## When false the think loop is skipped entirely: the bot is inert. Derived from
## [difficulty] (PASSIVE → false) by Scenario._attach_brain().
var active: bool = true

## Physics ticks between successive think() passes. AI decisions are coarse and
## relatively expensive, so we deliberately think a few times per second rather
## than every tick (30 tps → THINK_INTERVAL_TICKS=15 ≈ twice per second).
const THINK_INTERVAL_TICKS: int = 15

## HP fraction at or below which a unit is considered "at risk" for preservation.
const PRESERVATION_HP_THRESHOLD: float = 0.25

## The Bot (a Commander subclass carrying the perception API) this brain drives.
var bot: Bot

## Strategy layer — built lazily on the first think() once the Bot's map is
## resolved. The actuator is the shared command-issuing surface; the managers
## decide and call into it.
var _actuator: BotActuator
var _economy: BotEconomy
var _military: BotMilitary
var _production: BotProduction
var _targeting: BotTargeting
var _kamikaze: BotKamikaze
var _ordnance: BotOrdnance
var _scout: BotScout
## Opportunistic, utility-driven decisions (e.g. Warlords liberating Shelters for free
## units). Extensible: new utility decisions register as gatherers inside it.
var _opportunist: BotOpportunist
## Persistent, fog-limited belief about the enemy (last-known positions of seen
## units/structures). Refreshed first each think; available to the managers.
var _blackboard: BotBlackboard

var _ticks_since_think: int = 0

## Accumulated physics time (seconds) since preservation last ran.
var _preservation_elapsed: float = 0.0


func _ready() -> void:
	bot = get_parent() as Bot
	if bot == null:
		push_warning("BotBrain expects to be a child of a Bot; found %s" % get_parent())


func _physics_process(delta: float) -> void:
	if not active or bot == null or Engine.is_editor_hint():
		return
	_preservation_elapsed += delta
	if _preservation_elapsed >= 1.0:
		_preservation_elapsed -= 1.0
		_tick_preservation(delta)
	_ticks_since_think += 1
	if _ticks_since_think < THINK_INTERVAL_TICKS:
		return
	_ticks_since_think = 0
	think()


## Decision entry point, run on the throttled cadence above. Runs the strategy
## managers in priority order: production fills idle buildings; military steers
## the army. Economy expansion (mines/dwellings) joins here in a later milestone.
func think() -> void:
	if not _ensure_managers():
		return
	# Fold current vision into the persistent enemy belief before any manager runs.
	_blackboard.update()
	_economy.tick()
	_production.tick()
	# Before the military's idle-sweep: opportunistic utility actions (liberation,
	# future utility-gain decisions) claim units (e.g. Warlords) so they read as
	# non-idle and aren't yanked into an AttackMove this same tick.
	_opportunist.tick()
	# Scout before military: a unit given a move command here is non-idle when the
	# military's idle-sweep runs, protecting it from an immediate AttackMove override.
	_scout.tick()
	_military.tick()
	# Last: refine per-unit targets (defend against threats). Runs after the
	# military's objective tasking so a threatened unit's reaction takes priority.
	_targeting.tick()
	# AOE-suicide drones are micro'd separately (cost-effective blasts only), on a
	# slow ~7s cadence of their own.
	_kamikaze.tick()
	# Commander-level ordnances (faction abilities): defend the base, else strike.
	_ordnance.tick()


## The scout manager, or null before the strategy layer is built (first think). Lets a
## scenario / debugger read scouting coverage (BotScout.observed_fraction).
func get_scout() -> BotScout:
	return _scout


## Build the strategy layer once the Bot's map is available (Bot._ready resolves
## it from the scenario). Returns false until then so think() no-ops safely.
func _ensure_managers() -> bool:
	if _military != null:
		return true
	if bot == null or bot.map == null:
		return false
	_actuator = BotActuator.new(bot.map)
	_blackboard = BotBlackboard.new(bot)
	bot.blackboard = _blackboard  # let perception/composition read believed enemies
	_economy = BotEconomy.new(bot, _actuator)
	_production = BotProduction.new(bot, _actuator)
	_military = BotMilitary.new(bot, _actuator)
	_targeting = BotTargeting.new(bot, _actuator)
	_kamikaze = BotKamikaze.new(bot, _actuator)
	# Ordnances fire through the ScenarioTriggerManager (the event host), resolved
	# from the scenario. Null when a scene has none → BotOrdnance.tick no-ops.
	var manager := bot.scenario.get_node_or_null("ScenarioTriggerManager") as ScenarioTriggerManager \
		if bot.scenario != null else null
	_ordnance = BotOrdnance.new(bot, _actuator, manager)
	_scout = BotScout.new(bot, _actuator)
	_opportunist = BotOpportunist.new(bot, _actuator)
	return true


# ─── UNIT PRESERVATION ──────────────────────────────────────────────────────

## Whether this bot should attempt to save [unit] from destruction.
## Easy / Passive: never. Medium: only units costing ≥ 250 ore. Hard+: always.
func _should_preserve(unit: Commandable) -> bool:
	match difficulty:
		PlayerSlot.Difficulty.PASSIVE, PlayerSlot.Difficulty.EASY:
			return false
		PlayerSlot.Difficulty.MEDIUM:
			var spec: TechnologySpec = bot.technology_mapping.get(unit.type)
			return spec != null and spec.ore_cost >= 250
		_:  # HARD, IMPOSSIBLE
			return true


## Called every second from _physics_process. For each owned unit that _should_preserve
## AND is at-risk (hp ≤ PRESERVATION_HP_THRESHOLD) AND has no effective targets in
## aggro range AND is actively fighting (Attack or AttackMove command), cancel the
## fight and move the unit home.
func _tick_preservation(_delta: float) -> void:
	if _actuator == null:
		return
	for unit: Commandable in bot.get_units():
		if not _should_preserve(unit):
			continue
		if unit.defense == null:
			continue
		if unit.defense.hp / unit.defense.hp_max > PRESERVATION_HP_THRESHOLD:
			continue
		if not _no_effective_targets_in_aggro(unit):
			continue
		var cmd: Command = unit.current_command()
		if not (cmd is Attack or cmd is AttackMove):
			continue
		unit.update_commands(null)
		var garrison_host: Commandable = bot.nearest_garrison_for(unit)
		if garrison_host != null:
			_actuator.garrison_into(unit, garrison_host)
		else:
			_actuator.move([unit], _preservation_retreat_dest(unit))


## True when the unit has enemies in its aggro range but cannot effectively damage
## any of them (unit_effectiveness_vs returns 0 for every target). Returns false
## — i.e. "don't retreat on this gate" — when the range is empty, since an
## attack-moving unit with no enemies nearby isn't in a bad matchup yet.
func _no_effective_targets_in_aggro(unit: Commandable) -> bool:
	var nearby: Array = bot.get_enemies_in_aggro_range(unit)
	if nearby.is_empty():
		return false
	for enemy: Commandable in nearby:
		if bot.unit_effectiveness_vs(unit.type, enemy) > 0.0:
			return false
	return true


## Retreat destination for [unit]: nearest own structure, or base centroid as
## fallback when the bot has no structures left.
func _preservation_retreat_dest(unit: Commandable) -> Vector3:
	var nearest: Commandable = bot.nearest_own_structure(unit.global_position)
	if nearest != null:
		return nearest.global_position
	return bot.base_centroid()
