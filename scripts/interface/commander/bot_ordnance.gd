class_name BotOrdnance
extends RefCounted

## BotOrdnance — deploys the bot's commander-level Ordnances.
##
## Policy (the human's intent, automated): DEFEND first, else ATTACK.
##   • Base under threat → the engagement is the most-threatened structure and the
##     enemies pressuring it.
##   • Otherwise, if worthwhile enemy units are visible → the engagement is the
##     enemy army.
##   • Otherwise hold (don't waste a charge).
##
## WHERE within that engagement a drop lands depends on the Ordnance's Targeting:
##   • ENEMY_CLUSTER — the densest cluster of enemy units, to maximise an area
##     effect (e.g. Irradiate). Skipped unless it would catch >= min_targets.
##   • REINFORCE — where spawned allies should appear: the defended structure when
##     defending, our side of the front when attacking (e.g. Ambush).
##
## The bot earns its ordnances the same way the human does: it greedily unlocks any
## ordnance in its OrdnanceArsenal whose prerequisites are met and that it can afford
## (dominion accrued from veteran Warlords), then deploys whatever it owns. Cooldowns
## are ticked here off real elapsed time (the brain thinks ~2×/s), so the bot honours
## the same per-ordnance cooldown the human does.

enum Mode { DEFEND, ATTACK }

## Enemy units within this distance of an owned structure count as pressuring the
## base → DEFEND. Mirrors BotMilitary.DEFEND_THREAT_RADIUS so the two agree on what
## "under threat" means.
const DEFEND_THREAT_RADIUS: float = 10.0

## When attacking, how far from our army centroid toward the enemy cluster a
## REINFORCE drop lands (0 = on us, 1 = on them). Midway, so spawned allies join the
## front instead of materialising inside the enemy.
const REINFORCE_PUSH: float = 0.5

var _bot: Bot
var _act: BotActuator
var _manager: ScenarioTriggerManager
var _arsenal: OrdnanceArsenal
var _last_time: float


func _init(a_bot: Bot, a_act: BotActuator, a_manager: ScenarioTriggerManager) -> void:
	_bot = a_bot
	_act = a_act
	_manager = a_manager
	_arsenal = a_bot.ordnance_arsenal
	_last_time = a_bot.seconds_elapsed()


func tick() -> void:
	var owned: Array = _owned()
	_tick_cooldowns(owned)
	# Spend accrued dominion on whatever the bot can now reach in its ordnance DAG,
	# then deploy from the (possibly grown) owned set.
	_unlock_affordable()
	owned = _owned()
	if _manager == null or owned.is_empty():
		return
	# Nothing ready → no decision to make this tick.
	if not owned.any(func(o: Ordnance): return o.is_ready()):
		return
	var zone: Variant = _engagement_zone()
	if zone == null:
		return
	for ordnance: Ordnance in owned:
		if not ordnance.is_ready():
			continue
		var target: Variant = _aim(ordnance, zone)
		if target != null:
			ordnance.activate(target as Vector3, _manager, _bot.id)


## The live Ordnance instances the bot has unlocked so far.
func _owned() -> Array:
	return _arsenal.owned_ordnances() if _arsenal != null else []


## Unlock every ordnance currently within reach: prerequisites satisfied (any-of) and
## affordable. Run each tick, so the bot walks its DAG as dominion accumulates.
func _unlock_affordable() -> void:
	if _arsenal == null:
		return
	for entry: OrdnanceArsenal.Entry in _arsenal.entries:
		if _arsenal.is_available(entry) and _arsenal.can_afford(entry):
			_arsenal.try_unlock(entry)


## Advance the owned ordnances' cooldowns by the real time elapsed since the last tick.
func _tick_cooldowns(owned: Array) -> void:
	var now: float = _bot.seconds_elapsed()
	var dt: float = maxf(0.0, now - _last_time)
	_last_time = now
	for ordnance: Ordnance in owned:
		ordnance.tick(dt)


## The current engagement to focus ordnances on, as
## { "mode": Mode, "enemies": Array[Commandable], "anchor": Vector3 }, or null when
## neither defence nor a worthwhile attack applies (hold).
func _engagement_zone() -> Variant:
	var threatened: Commandable = _bot.most_threatened_structure(DEFEND_THREAT_RADIUS)
	if threatened != null:
		var defenders: Array = _enemy_units(
			_bot.get_enemies_near(threatened.global_position, DEFEND_THREAT_RADIUS)
		)
		if not defenders.is_empty():
			return {"mode": Mode.DEFEND, "enemies": defenders, "anchor": threatened.global_position}
	var visible: Array = _enemy_units(_bot.visible_enemies())
	if not visible.is_empty():
		return {"mode": Mode.ATTACK, "enemies": visible, "anchor": _home_or_army()}
	return null


## The world position to drop `ordnance` for the given engagement, or null when no
## worthwhile target exists for it.
func _aim(ordnance: Ordnance, zone: Dictionary) -> Variant:
	match ordnance.targeting:
		Ordnance.Targeting.ENEMY_CLUSTER:
			var cluster: Dictionary = _densest_cluster(zone["enemies"], ordnance.effect_radius)
			if cluster["count"] >= ordnance.min_targets:
				return cluster["center"]
			return null
		Ordnance.Targeting.REINFORCE:
			if zone["mode"] == Mode.DEFEND:
				return zone["anchor"]  # spawn defenders at the structure under attack
			# Attacking: land allies on our side of the front, toward the cluster.
			var cluster: Dictionary = _densest_cluster(zone["enemies"], ordnance.effect_radius)
			if cluster["count"] <= 0:
				return null
			return (zone["anchor"] as Vector3).lerp(cluster["center"], REINFORCE_PUSH)
	return null


## Mobile enemy units only (drop structures) from a list of commandables.
func _enemy_units(enemies: Array) -> Array:
	return enemies.filter(func(e: Commandable): return not e.has_node("Structure"))


## The enemy cluster a single `radius` drop would catch most of:
## { "center": Vector3 (centroid of the caught units), "count": int }. Centres the
## scan on each enemy and counts the others within radius — the same neighbourhood
## idea BotKamikaze uses to value a blast. Typed Node3D because it reads nothing but
## position; production passes Commandables (which are Node3Ds).
func _densest_cluster(enemies: Array, radius: float) -> Dictionary:
	var best_center: Vector3 = Vector3.ZERO
	var best_count: int = 0
	for e: Node3D in enemies:
		var c: Vector2 = VU.inXZ(e.global_position)
		var members: Array = enemies.filter(
			func(o: Node3D): return VU.inXZ(o.global_position).distance_to(c) <= radius
		)
		if members.size() > best_count:
			best_count = members.size()
			var sum: Vector3 = Vector3.ZERO
			for m: Node3D in members:
				sum += m.global_position
			best_center = sum / float(members.size())
	return {"center": best_center, "count": best_count}


## Anchor for offensive reinforcement: the army's centre of mass if we have units,
## else the base centroid.
func _home_or_army() -> Vector3:
	if _bot.army_size() > 0:
		return _bot.army_centroid()
	return _bot.base_centroid()
