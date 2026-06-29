class_name BotMilitary
extends RefCounted

## BotMilitary — the army's posture FSM.
##
## Each think pass it picks a posture from the Bot's senses and points the army at
## a single rally/objective world position via the actuator:
##   • DEFEND — an enemy is pressuring the base: converge on the most-threatened
##     structure and engage.
##   • ATTACK — the army is big enough: march on the nearest enemy structure.
##   • MASS   — otherwise: gather at the base and wait to build up.
##
## To avoid re-pathing every tick, the whole army is only re-tasked when the
## posture or objective actually changes; in between, only newly-idle units (e.g.
## freshly trained, or done fighting) are picked up and sent to the current
## objective.

enum Posture { MASS, ATTACK, DEFEND }

## Minimum combat units before the bot commits to an attack. Low for now so the
## opening armies actually clash; a difficulty/aggression knob later.
const ATTACK_ARMY_THRESHOLD: int = 3

## Enemy units within this distance (world units) of an owned structure count as
## pressuring the base → DEFEND. Deliberately tighter than Bot.is_base_under_threat's
## 30-unit default, which on a small map flags the *enemy's stationary base* as a
## permanent threat and makes the bot turtle forever.
const DEFEND_THREAT_RADIUS: float = 10.0

## How far the objective must move (world units) before counting as "changed"
## and re-tasking the whole army. Keeps a wandering enemy target from thrashing.
const OBJECTIVE_EPSILON: float = 3.0

## CONTEXTUAL attack commitment: launch a wave when our army value is at least
## ATTACK_RATIO × the BELIEVED enemy army value — i.e. attack when we're ahead, to
## punish, not on a blind timer.
const ATTACK_RATIO: float = 1.3
## Anti-stalemate escalation: the required ratio decays this much per second the bot
## holds a standing army WITHOUT committing. Two evenly-matched bots that can't
## out-produce each other would otherwise build forever; instead the bar relaxes until
## someone commits and the deadlock resolves into a fight.
const STALEMATE_ESCALATION_PER_SEC: float = 0.02
## …but never below this — don't throw a clearly-losing army away (the behind bot
## turtles and lets the stronger bot's aggression end the game).
const MIN_ATTACK_RATIO: float = 0.85
## Don't consider attacking until the army is at least worth this (no army yet ≠ a
## stalemate). Resets the escalation clock below it.
const MIN_ATTACK_ARMY_VALUE: float = 300.0
## Floor on the believed-enemy value in the ratio — avoids div-by-zero and stops an
## unseen/empty enemy from reading as infinitely beatable.
const ENEMY_VALUE_FLOOR: float = 100.0
## Time constant (seconds) for the smoothed enemy-strength estimate to fade toward the
## current sighting. It ratchets UP instantly on a bigger sighting but decays only
## slowly when the enemy leaves view — so brief loss of vision doesn't read as "the
## enemy has no army" and make the bot recklessly over-confident.
const ENEMY_ESTIMATE_TAU: float = 30.0
## HUMILITY PRIOR. Under fog the bot compares its WHOLE army to only the SEEN slice of
## the enemy's, so it chronically over-rates its lead. We therefore never assume the
## (largely unseen) enemy is weaker than this fraction of our own army — unless we've
## actually SEEN more. This keeps the bot from reading phantom 5× advantages: attacks
## become escalation-driven (anti-stalemate) instead of blind, while a genuinely
## larger SEEN enemy still reads as such and is respected.
const ASSUMED_ENEMY_PARITY: float = 0.85
## A launched wave stays committed (ATTACK, overriding DEFEND) until the army is spent
## down to this fraction of its launch value — so the bot doesn't dribble its army in.
const WAVE_SPENT_FRACTION: float = 0.35

var _bot: Bot
var _act: BotActuator

var _posture: Posture = Posture.MASS
var _objective: Vector3 = Vector3.ZERO
var _has_objective: bool = false

## Attack-wave + escalation state.
var _wave_active: bool = false
var _wave_launch_value: float = 0.0
var _stalemate_time: float = 0.0       # seconds holding an army without committing
var _last_eval_time: float = 0.0       # for the real-time escalation clock
var _enemy_value_estimate: float = 0.0 # smoothed (decayed-peak) belief of enemy army value


func _init(a_bot: Bot, a_act: BotActuator) -> void:
	_bot = a_bot
	_act = a_act


func tick() -> void:
	var posture: Posture = _decide_posture()
	var objective: Variant = _objective_for(posture)
	# No valid objective for the chosen posture (e.g. ATTACK with no enemies) —
	# fall back to massing at home.
	if objective == null:
		posture = Posture.MASS
		objective = _objective_for(Posture.MASS)
	if objective == null:
		return  # nothing to anchor on (no base and no units) — idle.

	var objective_pos: Vector3 = objective
	var changed: bool = (
		posture != _posture
		or not _has_objective
		or _objective.distance_to(objective_pos) > OBJECTIVE_EPSILON
	)
	_posture = posture
	_objective = objective_pos
	_has_objective = true

	# Re-task everyone on a posture/objective change; otherwise just sweep up
	# whatever units are currently idle and send them to the standing objective.
	# Only armed units fight — never march the unarmed technician to its death.
	var units: Array = _combat_units(_bot.get_units() if changed else _bot.get_idle_units())
	if units.is_empty():
		return
	_act.attack_move(units, objective_pos)


func current_posture() -> Posture:
	return _posture


func _decide_posture() -> Posture:
	# A committed attack wave OVERRIDES defence — once the bot has massed an army
	# worth a (randomised) cap, it pushes regardless of a scout poking the base.
	# This is the anti-turtle fix: DEFEND no longer wins unconditionally.
	if _committing_to_attack():
		return Posture.ATTACK
	if _bot.is_base_under_threat(DEFEND_THREAT_RADIUS):
		return Posture.DEFEND
	if _combat_units(_bot.get_units()).size() >= ATTACK_ARMY_THRESHOLD:
		return Posture.ATTACK
	return Posture.MASS


## True while the bot is committed to an attack wave. A wave launches when the army's
## ore value reaches the current cap (then the cap is re-rolled for next time) and
## stays committed until the army is spent to WAVE_SPENT_FRACTION of its launch value.
func _committing_to_attack() -> bool:
	var own: float = _bot.army_resource_value()

	# Time + smoothed enemy-strength estimate, refreshed every tick (even mid-wave, so
	# it's current when the wave ends). Robust to think cadence via real elapsed time.
	var now: float = _bot.seconds_elapsed()
	var dt: float = maxf(0.0, now - _last_eval_time)
	_last_eval_time = now
	var believed: float = _bot.believed_enemy_army_value()
	if believed >= _enemy_value_estimate:
		_enemy_value_estimate = believed  # jump up on a bigger sighting
	else:
		# Decay slowly toward the current (smaller) sighting — a momentary blind spot
		# mustn't read as "they have nothing".
		_enemy_value_estimate = lerp(_enemy_value_estimate, believed, clampf(dt / ENEMY_ESTIMATE_TAU, 0.0, 1.0))

	# Already committed: see the wave through until the army is spent, then regroup.
	if _wave_active:
		if own <= _wave_launch_value * WAVE_SPENT_FRACTION:
			_wave_active = false
			_stalemate_time = 0.0
		return _wave_active

	# No army worth committing yet — building up isn't a stalemate.
	if own < MIN_ATTACK_ARMY_VALUE:
		_stalemate_time = 0.0
		return false

	# Apply the humility prior: assume the enemy is at least ASSUMED_ENEMY_PARITY × our
	# own army unless we've actually seen more.
	var enemy_estimate: float = maxf(_enemy_value_estimate, own * ASSUMED_ENEMY_PARITY)
	var ratio: float = own / maxf(enemy_estimate, ENEMY_VALUE_FLOOR)
	# Bar starts at ATTACK_RATIO and relaxes the longer we hold without fighting, so a
	# parity deadlock eventually forces a commit (but never below MIN_ATTACK_RATIO).
	var threshold: float = maxf(MIN_ATTACK_RATIO, ATTACK_RATIO - _stalemate_time * STALEMATE_ESCALATION_PER_SEC)

	if ratio >= threshold:
		_wave_active = true
		_wave_launch_value = own
		_stalemate_time = 0.0
		return true

	_stalemate_time += dt
	return false


## Units we send to fight: every ARMED unit EXCEPT one that's currently
## constructing. "Armed" means a Loadout that actually holds a Weapon — an empty
## Loadout (e.g. the colonial Stock Truck, a not-yet-functional utility unit) has
## a weapon_inventory node but no weapons, so it must NOT be marched into combat.
## Build-capable units (Irregulars) are combat units too and fight normally; we just
## don't interrupt the one the economy pulled to build/repair a structure (it rejoins
## the army once it's done).
func _combat_units(units: Array) -> Array:
	return units.filter(func(u: Commandable):
		return u.weapon_inventory != null \
			and u.weapon_inventory.has_weapons() \
			and not BotEconomy._is_constructing(u) \
			and not BotOpportunist.is_committed(u) \
			and not _bot.is_suicide_aoe_unit(u))  # kamikazes are micro'd by BotKamikaze


## The world position to rally on for `posture`, or null when none applies.
func _objective_for(posture: Posture) -> Variant:
	match posture:
		Posture.DEFEND:
			var threatened: Commandable = _bot.most_threatened_structure()
			if threatened != null:
				return threatened.global_position
			return _home_anchor()
		Posture.ATTACK:
			var target: Commandable = _bot.nearest_enemy_structure_to_base()
			if target != null:
				return target.global_position
			# No enemy structures: head for any enemy unit instead.
			var enemies: Array = _bot.get_enemy_units()
			if not enemies.is_empty():
				return (enemies.front() as Commandable).global_position
			return null
		_:  # MASS
			return _home_anchor()


## Where "home" is: the base centroid if we own structures, else the army's
## centre of mass, else null (nothing to anchor on).
func _home_anchor() -> Variant:
	var base: Vector3 = _bot.base_centroid()
	if base != Vector3.ZERO:
		return base
	if _bot.army_size() > 0:
		return _bot.army_centroid()
	return null
