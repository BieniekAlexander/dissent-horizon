class_name BotSanction
extends RefCounted

## BotSanction — deploys the bot's commander-level Sanctions.
##
## Policy (the human's intent, automated): DEFEND first, else ATTACK.
##   • Base under threat → the engagement is the most-threatened structure and the
##     enemies pressuring it.
##   • Otherwise, if worthwhile enemy units are visible → the engagement is the
##     enemy army.
##   • Otherwise hold (don't waste a charge).
##
## WHERE within that engagement a drop lands depends on the Sanction's Targeting:
##   • ENEMY_CLUSTER — the densest cluster of enemy units, to maximise an area
##     effect (e.g. Irradiate). Skipped unless it would catch >= min_targets.
##   • REINFORCE — where spawned allies should appear: the defended structure when
##     defending, our side of the front when attacking (e.g. Ambush).
##
## The bot earns its sanctions the same way the human does: it greedily unlocks any
## sanction in its SanctionGrid whose gates are open (parent owned, tier open) and
## that it can afford (dominion accrued from veteran Warlords), then deploys whatever
## it owns.
##
## AND IT CASTS THEM THE SAME WAY TOO — by issuing UseSanction through the actuator, which
## is the player's own route. This module decides WHICH sanction, WHICH caster and WHERE;
## every rule about whether the cast is allowed at all (unlocked, a real caster, built,
## powered, charged, target spotted) belongs to UseSanction and is asked there. Firing the
## event here instead was a second implementation of the player's action that nothing
## compared against the first.

enum Mode { DEFEND, ATTACK }

## Enemy units within this distance of an owned structure count as pressuring the
## base → DEFEND. The SAME parameter BotMilitary reads (BotDifficulty.defend_threat_radius,
## pushed into both by BotBrain._apply_config), so the two cannot drift on what "under
## threat" means — which they could while each held its own copy as a constant.
var defend_threat_radius: float = 10.0

## When attacking, how far from our army centroid toward the enemy cluster a
## REINFORCE drop lands (0 = on us, 1 = on them). Midway, so spawned allies join the
## front instead of materialising inside the enemy.
const REINFORCE_PUSH: float = 0.5

## Below this fraction of its hit points a unit counts as ENDANGERED — worth a charge to save.
## Half: above it the unit is in a fight, not losing one.
const ENDANGERED_HP_FRACTION: float = 0.5

## The scout manager, for the REVEAL targeting: what it has not seen is where a Scan goes,
## and what a Scan shows is stamped back. Assigned by BotBrain; null aims no reveal.
var scout: BotScout = null

## Whether this bot ever spends a sanction OFFENSIVELY. False for PASSIVE, which still
## defends its own base with one — "never attacks the player" is not "never uses an ability".
## See BotDifficulty.may_attack.
var may_attack: bool = true

## Work units per sanction considered, and for finding the engagement to aim at (BotScheduler
## counts work in units of roughly a microsecond on the calibration machine).
const SANCTION_WORK_UNITS: int = 40
const ENGAGEMENT_WORK_UNITS: int = 400

var _bot: Bot
var _act: BotActuator
var _sanction_grid: SanctionGrid
var _last_time: float


## No ScenarioTriggerManager is held any more. The bot used to carry one because it fired
## sanction events itself; now it issues a UseSanction like the player and the COMMAND
## resolves the event host, so knowing about the trigger manager is no longer this module's
## business at all.
func _init(a_bot: Bot, a_act: BotActuator) -> void:
	_bot = a_bot
	_act = a_act
	_sanction_grid = a_bot.sanction_grid
	_last_time = a_bot.seconds_elapsed()


## Returns the work units spent.
func tick() -> int:
	var owned: Array = _owned()
	# Spend accrued dominion on whatever the bot can now reach in its sanction tree,
	# then deploy from the (possibly grown) owned set.
	_unlock_affordable()
	owned = _owned()
	# A scene with no event host can run nothing a sanction would throw, so there is no
	# decision to make. Asked of the scenario each tick rather than cached, since the bot no
	# longer holds the host itself.
	var work: int = SANCTION_WORK_UNITS * (1 + owned.size())
	if owned.is_empty() or _bot.scenario_event_manager() == null:
		return work
	# Nothing with a ready caster → no decision to make this tick.
	if not owned.any(func(o: Sanction): return _ready_caster(o) != null):
		return work
	# The engagement is found once, lazily: a sanction aimed at the map or at the bot's own
	# dearest unit has a use with no fight on, and must not wait for one.
	var zone: Variant = null
	var zone_sought: bool = false
	for sanction: Sanction in owned:
		# The charge belongs to a BUILDING now, so the bot picks one that can fire rather than
		# asking the sanction whether it is ready. No caster owned (or all recharging) means
		# the bot simply has not got this ability available, exactly as for the player.
		var caster: Commandable = _ready_caster(sanction)
		if caster == null:
			continue
		if sanction.targeting_needs_engagement() and not zone_sought:
			zone = _engagement_zone()
			zone_sought = true
			work += ENGAGEMENT_WORK_UNITS
		if sanction.targeting_needs_engagement() and zone == null:
			continue
		# An un-aimed sanction has nowhere to be pointed, so the whole aim step is skipped.
		# It still waits for an engagement to be worth firing into — reaching here at all
		# means the bot has decided there is one.
		if not sanction.needs_target:
			_act.use_sanction(caster, sanction, Vector3.ZERO)
			continue
		var target: Variant = _aim(sanction, zone if zone != null else {})
		# Counted whether or not it aims: a sanction that is owned, charged and never finds a
		# target is the audit's "the bot cannot work out where to put it".
		_act.usage.record_action(
			"sanction_aim", sanction.ability_id, "aimed" if target != null else "no_target"
		)
		if target == null:
			continue
		# UseSanction's precondition refuses a fogged target (Sanction.can_target). The aim
		# points are derived from currently-visible enemies, so this normally passes; when it
		# does not — a cluster centroid that falls in a gap between two units' vision, say —
		# the order is not issued and the charge is simply held for the next tick.
		if target is Commandable:
			_act.use_sanction(caster, sanction, (target as Commandable).global_position, target)
		elif _act.use_sanction(caster, sanction, target as Vector3):
			if sanction.targeting == Sanction.Targeting.REVEAL and scout != null:
				scout.mark_revealed(target as Vector3, sanction.area_radius())
	return work


## The live Sanction instances the bot can actually fire: unlocked, and not upgraded
## out of play by a later cell in the same column (see SanctionGrid.is_superseded).
func _owned() -> Array:
	return _sanction_grid.deployable_sanctions() if _sanction_grid != null else []


## Unlock every sanction currently within reach: gates open and affordable. Run each
## tick, so the bot walks its tree as dominion accumulates.
##
## Swept to a FIXPOINT rather than in one pass, because a purchase opens gates for
## entries the pass may already be past — an earlier entry whose parent this one just
## bought, or (once the second unlock in a tier lands) every entry in the tier below.
## One pass would still get there on the next tick, but the result would depend on
## authored order, which the sanction grid deliberately treats as unordered.
func _unlock_affordable() -> void:
	if _sanction_grid == null:
		return
	var bought: bool = true
	while bought:
		bought = false
		for entry: SanctionGrid.Entry in _sanction_grid.entries:
			if _sanction_grid.is_available(entry) and _sanction_grid.can_afford(entry):
				bought = _sanction_grid.try_unlock(entry) or bought


## One of the bot's buildings that can cast `a_sanction` right now, or null. Cooldowns are
## no longer ticked here at all — each caster runs its own, from its own _physics_process.
## A caster already carrying a UseSanction is skipped: the charge is not spent until the
## command fulfils, so without this the bot would re-order the same cast every think until
## it fired.
func _ready_caster(a_sanction: Sanction) -> Commandable:
	for caster: Commandable in _bot.casters_of(a_sanction):
		var store: Abilities = _store_of(caster)
		if (
			store != null
			and store.is_ready(a_sanction.ability_id)
			and not (caster.current_command() is UseSanction)
		):
			return caster
	return null


func _store_of(a_caster: Commandable) -> Abilities:
	return a_caster.get_node_or_null("Abilities") as Abilities if a_caster != null else null


## The current engagement to focus sanctions on, as
## { "mode": Mode, "enemies": Array[Commandable], "anchor": Vector3 }, or null when
## neither defence nor a worthwhile attack applies (hold).
func _engagement_zone() -> Variant:
	var threatened: Commandable = _bot.most_threatened_structure(defend_threat_radius)
	if threatened != null:
		var defenders: Array = _enemy_units(
			_bot.get_enemies_near(threatened.global_position, defend_threat_radius)
		)
		if not defenders.is_empty():
			return {"mode": Mode.DEFEND, "enemies": defenders, "anchor": threatened.global_position}
	# A PASSIVE bot defends with its sanctions and never opens with one. Gated here rather than
	# in tick(), so the DEFEND branch above still fires for it — "never attacks the player" is
	# not "never uses an ability".
	if not may_attack:
		return null
	var visible: Array = _enemy_units(_bot.visible_enemies())
	if not visible.is_empty():
		return {"mode": Mode.ATTACK, "enemies": visible, "anchor": _home_or_army()}
	return null


## Where to put `sanction`: a world position for a ground cast, the unit for a single-unit
## one, or null when nothing worth the charge exists. `a_zone` is the engagement, or {} for
## a targeting that needs none (Sanction.targeting_needs_engagement).
func _aim(a_sanction: Sanction, a_zone: Dictionary) -> Variant:
	match a_sanction.targeting:
		Sanction.Targeting.ENEMY_CLUSTER:
			var cluster: Dictionary = _densest_cluster(
				a_zone["enemies"], _cluster_radius(a_sanction)
			)
			if cluster["count"] >= a_sanction.min_targets:
				return cluster["center"]
			return null
		Sanction.Targeting.REINFORCE:
			if a_zone["mode"] == Mode.DEFEND:
				return a_zone["anchor"]  # spawn defenders at the structure under attack
			# Attacking: land allies on our side of the front, toward the cluster.
			var cluster: Dictionary = _densest_cluster(
				a_zone["enemies"], _cluster_radius(a_sanction)
			)
			if cluster["count"] <= 0:
				return null
			return (a_zone["anchor"] as Vector3).lerp(cluster["center"], REINFORCE_PUSH)
		Sanction.Targeting.REVEAL:
			return _reveal_target()
		Sanction.Targeting.ENDANGERED_FRIEND:
			return _endangered_friend(a_sanction, a_zone)
		Sanction.Targeting.VALUABLE_FRIEND:
			return _valuable_friend(a_sanction)
	return null


## Unscouted ground nearest to where the enemy is believed to be — their nearest known
## structure, else the middle of the map, which is where an unfound enemy is most likely
## reached from. Null with no scout to ask, or nothing left to reveal.
func _reveal_target() -> Variant:
	if scout == null:
		return null
	var believed: Variant = _bot.nearest_believed_enemy_structure_position()
	var toward: Vector2
	if believed != null:
		toward = VU.in_xz(believed)
	elif _bot.map != null:
		toward = _bot.map.world_bounds().get_center()
	else:
		toward = VU.in_xz(_bot.base_centroid())
	return scout.reveal_point(toward)


## The bot's own unit in the engagement most worth saving: the dearest one below
## ENDANGERED_HP_FRACTION that the sanction's event will accept. Null when none is.
func _endangered_friend(a_sanction: Sanction, a_zone: Dictionary) -> Variant:
	var anchor: Vector3 = a_zone["anchor"]
	var best: Commandable = null
	var best_value: float = 0.0
	for unit: Commandable in _bot.get_units():
		if unit.defense == null or unit.defense.hp_max <= 0.0:
			continue
		var fraction: float = unit.defense.hp / unit.defense.hp_max
		if fraction >= ENDANGERED_HP_FRACTION:
			continue
		if unit.global_position.distance_to(anchor) > defend_threat_radius:
			continue
		if not a_sanction.accepts_target(unit, _bot):
			continue
		var value: float = float(_bot.unit_cost(unit.id)) * (1.0 - fraction)
		if value > best_value:
			best_value = value
			best = unit
	return best


## The bot's own dearest unit the sanction's event will accept, or null.
func _valuable_friend(a_sanction: Sanction) -> Variant:
	var best: Commandable = null
	var best_cost: int = -1
	for unit: Commandable in _bot.get_units():
		if not a_sanction.accepts_target(unit, _bot):
			continue
		var cost: int = _bot.unit_cost(unit.id)
		if cost > best_cost:
			best_cost = cost
			best = unit
	return best


## Mobile enemy units only (drop structures) from a list of commandables.
func _enemy_units(a_enemies: Array) -> Array:
	return a_enemies.filter(func(e: Commandable): return not e.structure_is_active())


## The enemy cluster a single `radius` drop would catch most of:
## { "center": Vector3 (centroid of the caught units), "count": int }.
##
## A thin reading of Bot.best_covered_point with every body weighted 1, so "how many does
## this catch" and BotKamikaze's "what is this blast worth" are now the same scan asked
## two different questions. Kept as a named method because what a SANCTION wants is a
## count against its min_targets, not a weight.
## The radius the bot scores a cluster cast by: the sanction's own area, or, for one that
## states none, UNSTATED_CLUSTER_RADIUS.
static func _cluster_radius(sanction: Sanction) -> float:
	var area: float = sanction.area_radius()
	return area if area > 0.0 else UNSTATED_CLUSTER_RADIUS


## The bot's guess at what a sanction stating no area covers — the radius every sanction used
## to inherit as a default. Private to the bot's scoring: it is never shown to the player, and
## it is a guess rather than a fact about any ability.
const UNSTATED_CLUSTER_RADIUS: float = 6.0


func _densest_cluster(a_enemies: Array, a_radius: float) -> Dictionary:
	var best: Dictionary = _bot.best_covered_point(
		a_enemies, a_radius, func(_u: Node3D): return 1.0
	)
	return {"center": best["center"], "count": int(best["weight"])}


## Anchor for offensive reinforcement: the army's centre of mass if we have units,
## else the base centroid.
func _home_or_army() -> Vector3:
	if _bot.army_size() > 0:
		return _bot.army_centroid()
	return _bot.base_centroid()
