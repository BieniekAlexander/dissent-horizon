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

var _bot: Bot
var _act: BotActuator

var _posture: Posture = Posture.MASS
var _objective: Vector3 = Vector3.ZERO
var _has_objective: bool = false


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
	if _bot.is_base_under_threat(DEFEND_THREAT_RADIUS):
		return Posture.DEFEND
	if _combat_units(_bot.get_units()).size() >= ATTACK_ARMY_THRESHOLD:
		return Posture.ATTACK
	return Posture.MASS


## Units we send to fight: every armed unit EXCEPT one that's currently
## constructing. Build-capable units (Warlords) are combat units too and fight
## normally; we just don't interrupt the one the economy pulled to build/repair a
## structure (it rejoins the army once it's done).
func _combat_units(units: Array) -> Array:
	return units.filter(func(u: Commandable):
		return u.weapon_inventory != null and not BotEconomy._is_constructing(u))


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
