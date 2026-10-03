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
## posture or objective actually changes. In between, an idle unit is handled by where it
## stands: a WAVE member that went idle (arrived, or its fight ended) presses on to the
## objective; a unit that is not in the wave is RESERVE, staged on the threat side of the
## base and released as a body once the reserve is worth a fraction of the wave. Before
## staging existed every idle unit walked to the objective alone, which is the one-at-a-time
## army the design note opens with. The wave and the reserve are the first two squads —
## gdd/systems/ai/squads-and-relations.md.

enum Posture { MASS, ATTACK, DEFEND }

## Minimum combat units before the bot commits to an attack — the AGGRESSION dial, set from
## BotDifficulty. The default is the value every tier used before difficulty was a knob, so a
## manager built without a brain behaves exactly as it did.
var army_commit_threshold: int = 3

## Whether this bot takes offensive action at all. False for PASSIVE, which still masses and
## still DEFENDS what it owns but never marches on anybody — a sparring partner rather than
## an inert one. See BotDifficulty.may_attack.
var may_attack: bool = true

## Enemy units within this distance (world units) of an owned structure count as
## pressuring the base → DEFEND. Deliberately tighter than Bot.is_base_under_threat's
## 30-unit default, which on a small map flags the *enemy's stationary base* as a
## permanent threat and makes the bot turtle forever.
##
## A PARAMETER (BotDifficulty.defend_threat_radius), shared with BotSanction so the two
## agree on what "under threat" means. The default is the value it had as a constant.
var defend_threat_radius: float = 10.0

## How far the objective must move (world units) before counting as "changed"
## and re-tasking the whole army. Keeps a wandering enemy target from thrashing.
const OBJECTIVE_EPSILON: float = 3.0

## CONTEXTUAL attack commitment: launch a wave when our army value is at least
## `attack_value_ratio` × the BELIEVED enemy army value — i.e. attack when we're ahead, to
## punish, not on a blind timer.
##
## A PARAMETER (BotDifficulty.attack_value_ratio): this is the bot's real aggression dial,
## the one `army_commit_threshold` only approximates by counting bodies.
var attack_value_ratio: float = 1.3
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
##
## A PARAMETER (BotDifficulty.assumed_enemy_parity). It is the bot's whole model of what it
## cannot see, which is why it is worth searching alongside `scout_unit_budget`: a bot that
## looks needs less of a prior than one that does not.
var assumed_enemy_parity: float = 0.85
## A launched wave stays committed (ATTACK, overriding DEFEND) until the army is spent
## down to this fraction of its launch value — so the bot doesn't dribble its army in.
const WAVE_SPENT_FRACTION: float = 0.35

## RETREAT. A wave is called off early — before it is spent — when the army has lost this
## much of its launch value AND BotMomentum says the bot is actively bleeding.
##
## Both halves are load-bearing. Losses alone are not a reason to leave: a wave that trades
## a third of itself for the enemy's army has WON, and the old rule of running until spent
## to 35% exists because a bot that pulls back on damage dribbles its army in one squad at a
## time. The momentum test is what distinguishes "this is costing us" from "this is costing
## us FAST", and it is why retreating here is not a return to dribbling.
##
## A PARAMETER (BotDifficulty.wave_abort_fraction), and 0 restores the pre-retreat bot
## exactly: a wave that only ever ends by being spent.
var wave_abort_fraction: float = 0.70

## Seconds spent regrouping at home after a wave is called off, during which the bot will
## not commit again. Long enough to walk back and re-mass; without it the army-size branch
## in _decide_posture would re-launch the retreat the same think it began.
const REGROUP_SECONDS: float = 20.0

## STAGED REINFORCEMENTS. In ATTACK posture a combat unit that is not in the wave gathers at
## the staging point, and the reserve is released as a body once its value reaches this
## fraction of the wave's launch value — or the wave has nobody left in it. 0 is the old
## trickle: every idle unit walks to the objective alone the think it appears.
##
## A PARAMETER (BotDifficulty.reinforce_fraction).
var reinforce_fraction: float = 0.5

## How far forward of home the reserve stages, in world units: on the threat side of the
## base, so a released reserve starts its walk ahead of the buildings rather than through
## them, and short enough that the base's own defences still cover it.
const STAGING_OFFSET: float = 10.0

## A staged unit this close to the staging point (world units) is left standing rather than
## re-ordered every think — arriving is a navigation radius, not a point, and a unit told to
## walk to where it stands swirls.
const STAGING_RADIUS: float = 4.0

var _bot: Bot
var _act: BotActuator
## Whether the bot is winning or losing; what turns a costly push into a retreat.
var _momentum: BotMomentum

var _posture: Posture = Posture.MASS
var _objective: Vector3 = Vector3.ZERO
var _has_objective: bool = false

## Attack-wave + escalation state.
var _wave_active: bool = false
var _wave_launch_value: float = 0.0
var _stalemate_time: float = 0.0  # seconds holding an army without committing
var _last_eval_time: float = 0.0  # for the real-time escalation clock
var _enemy_value_estimate: float = 0.0  # smoothed (decayed-peak) belief of enemy army value
## seconds_elapsed() until which a called-off wave is regrouping and will not re-commit.
var _regroup_until: float = 0.0

## Instance id → true for every unit in the field with the current wave. The reserve is every
## other combat unit. Keyed by id so a dead member needs no reference to drop.
var _wave_members: Dictionary = {}
## Where the production structures were last told to rally, so the order is re-issued only
## when the point moves (or to a structure that has none yet).
var _rally_point: Vector3 = Vector3.ZERO
var _has_rally: bool = false

## Which manager owns which unit; the brain replaces this with the bot's shared registry. A
## fresh one by default, so a bare manager in a test sees every unit unclaimed.
var claims: BotClaims = BotClaims.new()

## Work units per unit considered for the army (BotScheduler counts work in units of roughly a
## microsecond on the calibration machine).
const UNIT_WORK_UNITS: int = 50


func _init(a_bot: Bot, a_act: BotActuator, a_momentum: BotMomentum = null) -> void:
	_bot = a_bot
	_act = a_act
	_momentum = a_momentum


## Returns the work units spent.
func tick() -> int:
	var considered: int = _bot.get_units().size()
	var posture: Posture = _decide_posture()
	var objective: Variant = _objective_for(posture)
	# No valid objective for the chosen posture (e.g. ATTACK with no enemies) —
	# fall back to massing at home.
	if objective == null:
		posture = Posture.MASS
		objective = _objective_for(Posture.MASS)
	if objective == null:
		return considered * UNIT_WORK_UNITS  # nothing to anchor on (no base and no units) — idle.

	var objective_pos: Vector3 = objective
	var changed: bool = (
		posture != _posture
		or not _has_objective
		or _objective.distance_to(objective_pos) > OBJECTIVE_EPSILON
	)
	_posture = posture
	_objective = objective_pos
	_has_objective = true

	# Re-task everyone on a posture/objective change. Otherwise an idle unit goes where it
	# belongs: in ATTACK that is the wave or the reserve (_tick_reinforcements); in MASS and
	# DEFEND every idle unit is swept to the standing objective. Only units with combat
	# utility fight — never march the unarmed technician to its death.
	if changed:
		var units: Array = _combat_units(_bot.get_units())
		_wave_members.clear()
		if posture == Posture.ATTACK:
			for unit: Commandable in units:
				_wave_members[unit.get_instance_id()] = true
		if not units.is_empty():
			_act.attack_move(units, objective_pos)
	elif posture == Posture.ATTACK:
		_tick_reinforcements(objective_pos)
	else:
		var idle: Array = _combat_units(_bot.get_idle_units())
		if not idle.is_empty():
			_act.attack_move(idle, objective_pos)
	_rally_production(
		_staging_point(objective_pos) if posture == Posture.ATTACK else objective_pos, changed
	)
	return considered * UNIT_WORK_UNITS


## ATTACK posture, nothing changed: press a wave member that went idle on to the objective;
## stage every reserve unit; release the reserve as a body when it is worth sending.
func _tick_reinforcements(a_objective: Vector3) -> void:
	var idle_wave: Array = _combat_units(_bot.get_idle_units()).filter(_is_wave_member)
	if not idle_wave.is_empty():
		_act.attack_move(idle_wave, a_objective)
	var reserve: Array = _combat_units(_bot.get_units()).filter(
		func(u: Commandable) -> bool: return not _is_wave_member(u)
	)
	if reserve.is_empty():
		return
	if _wave_is_spent() or _reserve_value(reserve) >= reinforce_fraction * _wave_launch_value:
		for unit: Commandable in reserve:
			_wave_members[unit.get_instance_id()] = true
		_act.attack_move(reserve, a_objective)
		return
	var staging: Vector3 = _staging_point(a_objective)
	var to_stage: Array = reserve.filter(
		func(u: Commandable) -> bool:
			return not u.has_command() and u.global_position.distance_to(staging) > STAGING_RADIUS
	)
	if not to_stage.is_empty():
		_act.attack_move(to_stage, staging)


func _is_wave_member(a_unit: Commandable) -> bool:
	return _wave_members.has(a_unit.get_instance_id())


## True when no wave member is still alive — the reserve is then the whole army, and holding
## it back would leave the objective to nobody. Dead members are dropped as they are found.
func _wave_is_spent() -> bool:
	for id: int in _wave_members.keys():
		if is_instance_id_valid(id):
			return false
		_wave_members.erase(id)
	return true


## What the reserve is worth, in the energy the wave's launch value is measured in.
func _reserve_value(a_reserve: Array) -> float:
	var total: float = 0.0
	for unit: Commandable in a_reserve:
		total += float(_bot.unit_cost(unit.id))
	return total


## Where the reserve gathers: STAGING_OFFSET from home toward the objective, so it stands on
## the threat side of the base. Home itself when the objective is home.
func _staging_point(a_objective: Vector3) -> Vector3:
	var home: Vector3 = _home_anchor_position()
	var toward: Vector3 = a_objective - home
	if toward.length_squared() <= STAGING_OFFSET * STAGING_OFFSET:
		return home
	return home + toward.normalized() * STAGING_OFFSET


## Point every production structure's rally at `a_point`: re-issued to all of them when the
## point moves, and otherwise only to a structure that has no rally yet (one finished since).
## A new unit then walks to where the military wants it on its own, instead of standing at
## the door until the idle sweep finds it.
func _rally_production(a_point: Vector3, a_moved: bool) -> void:
	var moved: bool = (
		a_moved or not _has_rally or _rally_point.distance_to(a_point) > OBJECTIVE_EPSILON
	)
	_rally_point = a_point
	_has_rally = true
	var structures: Array = _bot.get_production_structures().filter(
		func(s: Commandable) -> bool: return moved or s.rally_commands.is_empty()
	)
	if not structures.is_empty():
		_act.rally(structures, a_point)


func current_posture() -> Posture:
	return _posture


## How many units are in the field with the current wave. An instrument for the self-play
## harness, which observes the bot and never issues; no manager reads it.
func wave_size() -> int:
	var live: int = 0
	for id: int in _wave_members.keys():
		if is_instance_id_valid(id):
			live += 1
	return live


## How many combat units are held in reserve — not in the wave. Only meaningful in ATTACK
## posture; outside it every combat unit is "reserve" and the number is the army's size.
func reserve_size() -> int:
	return (
		_combat_units(_bot.get_units())
		. filter(func(u: Commandable) -> bool: return not _is_wave_member(u))
		. size()
	)


func _decide_posture() -> Posture:
	# A PASSIVE bot has exactly two postures. It answers something walking into its base and
	# otherwise gathers; nothing it does ever leaves home. Checked before everything, because
	# "never attacks the player" is not a threshold it could cross.
	if not may_attack:
		return Posture.DEFEND if _bot.is_base_under_threat(defend_threat_radius) else Posture.MASS
	# A committed attack wave OVERRIDES defence — once the bot has massed an army
	# worth a (randomised) cap, it pushes regardless of a scout poking the base.
	# This is the anti-turtle fix: DEFEND no longer wins unconditionally.
	if _committing_to_attack():
		return Posture.ATTACK
	if _bot.is_base_under_threat(defend_threat_radius):
		return Posture.DEFEND
	# ATTACK is only ever a live wave. The body count used to return ATTACK here on its own,
	# WITHOUT launching a wave — so the retreat rule, the spent fraction and the regroup
	# window never applied to it, and the value comparison was decorative whenever the count
	# was met. The count is now the first gate of _committing_to_attack, in series.
	return Posture.MASS


## True while the bot is committed to an attack wave. A wave launches when the army is big
## enough in BODIES (army_commit_threshold) and ahead enough in VALUE (the ratio below), and
## stays committed until the army is spent to WAVE_SPENT_FRACTION of its launch value or
## the retreat rule calls it off.
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
		_enemy_value_estimate = lerp(
			_enemy_value_estimate, believed, clampf(dt / ENEMY_ESTIMATE_TAU, 0.0, 1.0)
		)

	# Already committed: see the wave through — unless it is going badly enough to leave.
	if _wave_active:
		if own <= _wave_launch_value * WAVE_SPENT_FRACTION or _should_abort_wave(own):
			_end_wave()
		return _wave_active

	# Regrouping from a called-off wave: rebuild before committing again.
	if now < _regroup_until:
		return false

	# No army worth committing yet, in value or in bodies — building up isn't a stalemate.
	if (
		own < MIN_ATTACK_ARMY_VALUE
		or _combat_units(_bot.get_units()).size() < army_commit_threshold
	):
		_stalemate_time = 0.0
		return false

	# Apply the humility prior: assume the enemy is at least ASSUMED_ENEMY_PARITY × our
	# own army unless we've actually seen more.
	var enemy_estimate: float = maxf(_enemy_value_estimate, own * assumed_enemy_parity)
	var ratio: float = own / maxf(enemy_estimate, ENEMY_VALUE_FLOOR)
	# Bar starts at attack_value_ratio and relaxes the longer we hold without fighting, so a
	# parity deadlock eventually forces a commit (but never below MIN_ATTACK_RATIO).
	var threshold: float = maxf(
		MIN_ATTACK_RATIO, attack_value_ratio - _stalemate_time * STALEMATE_ESCALATION_PER_SEC
	)

	if ratio >= threshold:
		_wave_active = true
		_wave_launch_value = own
		_stalemate_time = 0.0
		return true

	_stalemate_time += dt
	return false


## RETREAT TEST: is this wave failing rather than merely costing something?
##
## Two conditions, and neither alone is enough — see wave_abort_fraction. False when the bot
## has no momentum signal (a manager built without one in a test), so the wave behaves
## exactly as it did before retreat existed.
func _should_abort_wave(a_own_value: float) -> bool:
	if _momentum == null:
		return false
	return a_own_value <= _wave_launch_value * wave_abort_fraction and _momentum.is_losing()


## Close out the wave and start the regroup window. The escalation clock restarts too: the
## bot has just fought, so it is not sitting in a stalemate.
func _end_wave() -> void:
	_wave_active = false
	_stalemate_time = 0.0
	_regroup_until = _bot.seconds_elapsed() + REGROUP_SECONDS


## Units we send to fight: everything with COMBAT UTILITY except one that is currently busy.
##
## Combat utility is armed OR able to crush (Bot.unit_has_combat_utility), and the second
## half is the correction: an armed-only test filtered the Colonial Stock Truck out of the
## re-task AND out of the idle sweep, so a truck with nothing to capture was claimed by
## nobody and stood still for the rest of the match. It is unarmed and it is not harmless —
## it runs light infantry over, which on this content is also how the Colonials take
## prisoners.
##
## Build-capable units (Irregulars) are combat units too and fight normally; we just don't
## interrupt the one the economy pulled to build/repair a structure (it rejoins the army once
## it's done), or the one the opportunist has already committed to an errand.
##
## A CLAIMED unit is never the army's: the army is what nobody else has claimed (BotClaims), so
## a scout, a unit mid-fight under BotTargeting, or one on an errand is left alone however the
## managers happen to be interleaved.
func _combat_units(a_units: Array) -> Array:
	return a_units.filter(
		func(u: Commandable):
			return (
				_bot.unit_has_combat_utility(u)
				and not claims.is_claimed(u)
				and not BotEconomy._is_constructing(u)
				and not BotOpportunist.is_committed(u)
				and not _bot.is_suicide_aoe_unit(u)
			)
	)  # kamikazes are micro'd by BotKamikaze


## The world position to rally on for `posture`, or null when none applies.
func _objective_for(a_posture: Posture) -> Variant:
	match a_posture:
		Posture.DEFEND:
			var threatened: Commandable = _bot.most_threatened_structure()
			if threatened != null:
				return threatened.global_position
			return _home_anchor()
		Posture.ATTACK:
			# FOG-LIMITED, deliberately: the army marches on what this bot has SEEN, never on the
			# live scene. An opponent it has not scouted yields no objective at all, tick() demotes
			# the posture to MASS, and the bot builds up at home until it finds somebody — which is
			# what makes scouting a precondition for aggression rather than a nicety. See
			# Bot.nearest_believed_enemy_structure_position and
			# gdd/systems/ai/bot-architecture.md §The attack objective is a belief.
			#
			# AND ACTIONABLE. Being fog-limited was never the only requirement: a belief is only an
			# objective if marching on it can lead to something happening. Two ways it cannot, both
			# measured in self-play and both reported from a watched match — see
			# gdd/systems/ai/bot-engagement-fixes.md §The objective nobody could act on:
			#   • NOTHING IN THE ARMY CAN HURT IT. An enemy Scan drone is a HOVERING piece on the
			#     air layer; a ground-only army has no targeting mode for it at all, so ordered
			#     onto it the whole army walks over, arrives, and stands there until the drone's
			#     lifespan runs out. `Bot.any_unit_can_damage` is that question.
			#   • THE WALK HAS ALREADY DISPROVED IT. A unit belief lapses only on a three-minute
			#     timer, so an army standing on the spot where it last saw an enemy scout keeps
			#     marching at ground it can see is empty. `Bot.belief_is_disproved` is that one.
			# Both are FILTERS, not rankings: a rejected belief is not a candidate, so the query
			# still answers with the nearest belief that IS actionable rather than with nothing.
			var army: Array = _combat_units(_bot.get_units())
			var actionable: Callable = func(entry: CommanderBlackboard.Entry) -> bool:
				return (
					Bot.any_unit_can_damage(army, entry.entity)
					and not _bot.belief_is_disproved(entry)
				)
			var believed_base: Variant = _bot.nearest_believed_enemy_structure_position(actionable)
			if believed_base != null:
				return believed_base
			# Nothing of theirs standing that we know of: go after the last place we saw a unit.
			return _bot.nearest_believed_enemy_unit_position(_home_anchor_position(), actionable)
		_:  # MASS
			return _home_anchor()


## `_home_anchor()` as a plain Vector3 — ZERO when there is nothing to anchor on. Used where
## the anchor is only a distance ORIGIN (which of several remembered positions is nearest)
## rather than a destination, so "nowhere" needs no separate branch.
func _home_anchor_position() -> Vector3:
	var anchor: Variant = _home_anchor()
	return anchor if anchor != null else Vector3.ZERO


## Where "home" is: the base centroid if we own structures, else the army's
## centre of mass, else null (nothing to anchor on).
func _home_anchor() -> Variant:
	var base: Vector3 = _bot.base_centroid()
	if base != Vector3.ZERO:
		return base
	if _bot.army_size() > 0:
		return _bot.army_centroid()
	return null
