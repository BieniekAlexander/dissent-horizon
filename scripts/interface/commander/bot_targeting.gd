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


func _init(a_bot: Bot, a_act: BotActuator) -> void:
	_bot = a_bot
	_act = a_act
	# v1 default mix: react to incoming threats only. A difficulty level would
	# instead build its own mix (e.g. also append effectiveness_signal, etc.).
	append_signal(1.0, threat_signal)


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
	# Candidates: nearby enemies this unit is actually able to attack.
	var candidates: Array = _bot.get_enemies_near(unit.global_position, scan_radius).filter(
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
## out of its own range) scores 0, so a unit chipping a building swings to whatever is
## actually shooting it. v1 is binary (1.0 = a live threat); combined with the commit
## margin, that means "drop a non-threat for any threat, then stay on it." Ranking
## threats BY MAGNITUDE is a future refinement — it needs a real per-weapon DPS figure
## (Loadout.total_damage() is currently broken: it reads a removed Weapon.damage field).
static func threat_signal(unit: Commandable, candidate: Commandable) -> float:
	if candidate.weapon_inventory == null:
		return 0.0
	var w: Weapon = candidate.weapon_inventory.weapon_for_target(unit)
	if w == null:
		return 0.0
	if not SU.is_in_attack_range(w, candidate, unit):
		return 0.0
	return 1.0

# Future signals (not registered in v1) would look like, e.g.:
#   static func effectiveness_signal(unit, candidate) -> float:
#       # how well `unit` damages `candidate` (DamageTable vs its armour/attributes)
#   static func finishability_signal(unit, candidate) -> float:
#       # bonus for low remaining HP — cheap kills worth finishing
# A difficulty config registers whichever mix it wants via append_signal().
