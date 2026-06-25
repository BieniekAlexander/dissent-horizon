class_name BotTargeting
extends RefCounted

## BotTargeting — bot-only combat retargeting.
##
## Players' units intentionally do NOT auto-retarget (that's where human mechanical
## skill lives); this logic runs only for bot-owned units and never touches the
## shared Attack/aggro path.
##
## It's a generic weighted-signal scorer rather than a set of hardcoded rules: each
## "signal" rates how desirable a candidate is as a target, signals are summed, and
## a unit switches to the best candidate ONLY if it beats the CURRENT target's score
## by [switch_margin]. Two properties keep it from feeling superhuman or jittery:
##   • commitment — the margin means a unit won't flip targets for a marginal gain;
##   • reaction latency — it re-evaluates on the brain's think cadence, not per frame.
##
## v1 registers a SINGLE signal (threat). Richer behaviour is purely additive:
## append_signal(weight, fn) with effectiveness / finishability / target-value / …,
## and a per-difficulty config can hand BotTargeting its own signal mix + margin +
## scan radius without changing this logic. (See the example signals at the bottom.)

## How far (world units) a unit notices threats worth reacting to.
const DEFAULT_SCAN_RADIUS: float = 8.0

var _bot: Bot
var _act: BotActuator

## Active scoring signals: each {weight: float, fn: Callable(unit, candidate) -> float}.
var _signals: Array = []
## A candidate must beat the current target's score by this factor to be worth
## switching to. > 1.0. Higher = more committed (and less twitchy / less optimal).
var switch_margin: float = 1.3
var scan_radius: float = DEFAULT_SCAN_RADIUS


## Default per-signal weights (the relative importance dial — a difficulty level
## would override these, or build a different signal mix entirely). Each signal is
## roughly normalised so the weights are comparable: threat 0/1, effectiveness ~a
## damage multiplier centred on 1, finishability 0..1, proximity 0..1.
const W_THREAT: float = 1.0
const W_EFFECTIVENESS: float = 1.0
const W_FINISHABILITY: float = 1.0
const W_PROXIMITY: float = 0.5


func _init(a_bot: Bot, a_act: BotActuator) -> void:
	_bot = a_bot
	_act = a_act
	# Default mix: prefer targets that threaten us, that we hit hard (good matchup),
	# that are nearly dead (cheap kills), and that are close — weighted by the W_*
	# constants. append_signal more / fewer to retune per difficulty.
	append_signal(W_THREAT, threat_signal)
	append_signal(W_EFFECTIVENESS, effectiveness_signal)
	append_signal(W_FINISHABILITY, finishability_signal)
	append_signal(W_PROXIMITY, proximity_signal)


## Register a scoring signal. fn(unit, candidate) -> float (higher = more desirable
## to attack). Summed × weight across all registered signals.
func append_signal(weight: float, fn: Callable) -> void:
	_signals.append({"weight": weight, "fn": fn})


func tick() -> void:
	for unit: Commandable in _bot.get_units():
		if unit.weapon_inventory == null:
			continue  # can't attack anything
		if BotEconomy._is_constructing(unit):
			continue  # don't yank the active builder mid-construction
		_retarget(unit)


func _retarget(unit: Commandable) -> void:
	# Candidates: enemies within this unit's OWN aggro range that it can attack.
	# Scoping to aggro range (not a fixed scan radius) keeps picks inside the
	# persist=false attack leash, so the chosen target sticks instead of being
	# instantly dropped as out-of-range and re-picked every think.
	var candidates: Array = _bot.get_enemies_near(unit.global_position, _engage_radius(unit)).filter(
		func(c: Commandable): return unit.weapon_inventory.weapon_for_target(c) != null
	)
	if candidates.is_empty():
		return
	var current: Commandable = _current_target(unit)
	var best: Commandable = _best_candidate(unit, current, candidates)
	if best != null and best != current:
		# persist=false: deal with the threat, then fall back to the army objective
		# (the military manager re-tasks the unit once it goes idle).
		_act.attack([unit], best, false)


## The unit's aggro-range XZ radius (how far it engages), falling back to scan_radius
## when it has no aggro shape. Bounds the retarget candidate scan so picks stay within
## the unit's engagement leash.
func _engage_radius(unit: Commandable) -> float:
	var shape_node: CollisionShape3D = unit.aggro_range_shape
	if shape_node == null:
		return scan_radius
	var scale: float = shape_node.global_transform.basis.x.length()
	var shp: Shape3D = shape_node.shape
	if shp is CylinderShape3D:
		return (shp as CylinderShape3D).radius * scale
	if shp is SphereShape3D:
		return (shp as SphereShape3D).radius * scale
	return scan_radius


## The enemy this unit is presently set to attack, or null (e.g. while attack-moving).
func _current_target(unit: Commandable) -> Commandable:
	if unit.has_command() and unit.current_command() is Attack:
		var t: Entity = unit.current_command().message.target
		if is_instance_valid(t):
			return t as Commandable
	return null


## Highest-scoring candidate that clears the commitment margin over the current
## target, or null to keep the current target. A null current target (attack-moving)
## means any positively-scored candidate qualifies.
func _best_candidate(unit: Commandable, current: Commandable, candidates: Array) -> Commandable:
	var threshold: float = _score(unit, current) * switch_margin if current != null else 0.0
	var best: Commandable = null
	var best_score: float = threshold
	for c: Commandable in candidates:
		var s: float = _score(unit, c)
		if s > best_score:
			best_score = s
			best = c
	return best


func _score(unit: Commandable, candidate: Commandable) -> float:
	if candidate == null or not is_instance_valid(candidate):
		return 0.0
	var total: float = 0.0
	for sig: Dictionary in _signals:
		total += sig["weight"] * (sig["fn"] as Callable).call(unit, candidate)
	return total


# ─── SIGNALS ────────────────────────────────────────────────────────────────
# Each signal is static, (unit, candidate) -> float, higher = more desirable to
# attack. Keep them cheap (they run per unit per candidate per think).

## THREAT — does `candidate` pose a present danger to `unit`: it can target `unit`
## AND is currently positioned to hit it. A harmless target (a building, or an enemy
## out of its own range) scores 0. Binary (1.0 = a live threat), so combined with the
## commit margin it means "drop a non-threat for any threat, then stay on it."
static func threat_signal(unit: Commandable, candidate: Commandable) -> float:
	if candidate.weapon_inventory == null:
		return 0.0
	var w: Weapon = candidate.weapon_inventory.weapon_for_target(unit)
	if w == null:
		return 0.0
	if not SU.is_in_attack_range(w, candidate, unit):
		return 0.0
	return 1.0


## EFFECTIVENESS — how good `unit`'s matchup is against `candidate`: the damage-table
## multiplier (after armour + attribute modifiers) of the weapon it would use, i.e.
## effective_damage / base_damage. 1.0 = neutral, >1 strong vs this target, <1 weak —
## so a unit gravitates to the enemies it actually hurts. (Multiplier, not absolute
## damage, so the signal is comparable across different-strength units.)
static func effectiveness_signal(unit: Commandable, candidate: Commandable) -> float:
	# Hand-set matchup override wins over the computed multiplier (parity with the
	# production effectiveness in Bot.unit_effectiveness_vs).
	var override: Variant = DamageTable.matchup_override(unit.type, candidate.type)
	if override != null:
		return override
	if unit.weapon_inventory == null:
		return 0.0
	var w: Weapon = unit.weapon_inventory.weapon_for_target(candidate)
	if w == null:
		return 0.0
	var base: float = w.per_shot_damage()
	if base <= 0.0:
		return 0.0
	return DamageTable.calculate_damage(base, w.per_shot_damage_type(), candidate) / base


## FINISHABILITY — how close `candidate` is to dying (lost HP fraction, 0..1). A
## nearly-dead target scores ~1, a full-health one ~0, so the bot prefers to finish
## off cheap kills rather than spread damage.
static func finishability_signal(_unit: Commandable, candidate: Commandable) -> float:
	var d: Defense = candidate.defense
	if d == null or d.hp_max <= 0.0:
		return 0.0
	return clampf(1.0 - d.hp / d.hp_max, 0.0, 1.0)


## PROXIMITY — prefer closer targets (less travel, faster to engage). Decreasing with
## XZ distance, self-normalising to (0, 1] (1 when adjacent, → 0 far away).
static func proximity_signal(unit: Commandable, candidate: Commandable) -> float:
	var dist: float = VU.inXZ(unit.global_position).distance_to(VU.inXZ(candidate.global_position))
	return 1.0 / (1.0 + dist)
