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
## The army is SQUADS, each kept to a policy (Squad, SquadPolicy): the MAIN body — the wave
## under ATTACK (AssaultPolicy), the army at home otherwise (HoldPolicy); the RESERVE, staged
## on the threat side of the base while a wave is out and released as a body once it is
## worth a fraction of the wave (StagePolicy); and the GUARD, the reserve turned to a
## threatened structure while the wave is away (HoldPolicy). How many of the three the bot
## may run is `squad_cap`, a difficulty parameter: one squad is the trickle — every new unit
## walks to the front alone — two is wave and reserve, three adds the guard. Dispatch is the
## squad's: a changed policy re-orders everyone, the same policy only the idle, so the army
## is never re-pathed to where it already stands. gdd/systems/ai/squads-and-relations.md.

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

## Under HEGEMONY a command centre is judged threatened at this multiple of
## defend_threat_radius: it is the whole game, so an enemy still some way off it is already a
## threat to it, and the army turns for it before a raid on any other building would call it.
const COMMAND_CENTRE_THREAT_MULTIPLIER: float = 2.0

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

## How many squads the military may run at once: 1 is one body (reinforcements walk to the
## front alone, the trickle), 2 is wave and reserve, 3 adds the guard. −1 lifts the cap. A
## PARAMETER (BotDifficulty.squad_cap); the default is the two squads the bot ran before the
## cap existed.
var squad_cap: int = 2

## How strong the guard is made against what it answers: units join it until their value
## against the threats (cost × matchup, the scale Bot.base_threats prices a threat on)
## reaches this multiple of the threat's value, and the rest of the reserve stays with the
## wave. 1 matches the threat; 2 brings twice it. A PARAMETER
## (BotDifficulty.guard_strength_ratio), searched rather than reasoned about (Alex, 2026-10-07).
var guard_strength_ratio: float = 1.5

## How far forward of home the reserve stages, in world units: on the threat side of the
## base, so a released reserve starts its walk ahead of the buildings rather than through
## them, and short enough that the base's own defences still cover it.
const STAGING_OFFSET: float = 10.0

## A unit this close to where it was sent has ARRIVED and is left standing — the policies'
## rule (PostPolicy.HOLD_RADIUS), named here for the stall radius below.
const HOLD_RADIUS: float = PostPolicy.HOLD_RADIUS

## A wave standing on its objective with nothing to fight for this long has found nothing it
## can act on there — the belief was not disproved because nothing walked into vision of it
## (a building across a cliff, a ridge) — and the objective is ABANDONED for a while so the
## next belief gets its turn. Longer than any approach the wave makes once it is this close.
const OBJECTIVE_STALL_SECONDS: float = 20.0
## How long an abandoned objective stays off the list. The ground may change — a wall comes
## down, a scout disproves it — so it is a cooldown, not a ban.
const OBJECTIVE_ABANDON_SECONDS: float = 120.0
## The wave counts as standing ON its objective within this of it (AssaultPolicy.STALL_RADIUS).
const STALL_RADIUS: float = AssaultPolicy.STALL_RADIUS

## How far the objective must move (world units) before counting as "changed"
## and re-tasking the whole army. Keeps a wandering enemy target from thrashing.
##
## Was 3.0, which did not: a believed UNIT's last-known location is refreshed every blackboard
## update while it is in sight, a walking unit covers three units in well under a combat
## period, and every "change" RE-LAUNCHES the wave — emptying every garrison and re-ordering
## the whole army — so the army flapped in and out of its bunkers at the think rate (observed
## 2026-10-06 on main). A drift within this radius is the SAME objective, moved: the wave
## presses on through _tick_reinforcements, which sends idle members to the new point. A jump
## beyond it is a different objective, and that is what a re-launch is for. Sized to the
## stall radius: an objective that has moved further than the wave's own spread around it is
## no longer where the wave is.
const OBJECTIVE_EPSILON: float = STALL_RADIUS * 2.0
## How far the rally point may drift before the producers are re-pointed. A rally is one
## order per structure and moves nothing, so it tracks closely.
const RALLY_EPSILON: float = 3.0
## How far the walk to a believed objective may end from it and still count as reaching it:
## a structure's half-footprint plus the standoff a wide unit keeps, since the path ends
## beside a building, never on it.
const REACH_TOLERANCE: float = 8.0

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

## The three squads, created on the bot's registry so the harness sees them beside a
## mission's. MAIN is the wave under ATTACK and the whole army otherwise; RESERVE and GUARD
## are empty outside ATTACK. See the class note and `squad_cap`.
var _main: Squad
var _reserve: Squad
var _guard: Squad
## The remembered ENTITY behind the ATTACK objective when it is a structure belief, or null —
## set by _objective_for(ATTACK) beside the position it returns, and handed to the wave's
## AssaultPolicy at launch, which orders an arrived member to ATTACK it. Untyped: a belief
## outlives the thing it remembers, and a freed object fails a typed field.
var _objective_entity: Variant = null
## Its instance id, kept apart from the reference so the belief can be asked about after the
## node is freed (a freed object cannot answer get_instance_id).
var _objective_id: int = 0
## seconds_elapsed() when the current objective was set, or the wave was last seen fighting
## or travelling — what OBJECTIVE_STALL_SECONDS is measured from.
var _objective_since: float = 0.0
## Abandoned objectives: [{"position": Vector3, "until": float}]. See OBJECTIVE_STALL_SECONDS.
var _abandoned_objectives: Array = []
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
	_main = _bot.squads.create(&"main")
	_reserve = _bot.squads.create(&"reserve")
	_guard = _bot.squads.create(&"guard")
	for squad: Squad in [_main, _reserve, _guard]:
		squad.eligible = _is_armys


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

	# Re-task on a posture/objective change: a new policy for the main body, which the squad
	# issues to everyone. Otherwise the squads carry on — a new unit joins the body it belongs
	# to, the reserve is released when it is worth sending, and each squad re-issues its
	# policy only to a member that went idle. Only units with combat utility fight — never
	# march the unarmed technician to its death.
	if changed:
		_objective_since = _bot.seconds_elapsed()
		if posture == Posture.ATTACK:
			_launch(objective_pos)
		else:
			_hold(objective_pos)
	elif posture == Posture.ATTACK:
		_retarget_wave(objective_pos)
		_tick_reinforcements(objective_pos)
		_check_objective_stall(objective_pos)
	else:
		_main.add_all(_combat_units(_bot.get_units()))
	_tick_squads()
	_rally_production(
		_staging_point(objective_pos) if posture == Posture.ATTACK else objective_pos, changed
	)
	return considered * UNIT_WORK_UNITS


## Every squad's dispatch: a changed policy to all its members, the same one to the idle.
func _tick_squads() -> void:
	for squad: Squad in [_main, _reserve, _guard]:
		squad.tick()


## Send the whole army at `a_objective` as the new wave, collecting first whatever is sitting
## in a bunker: a unit firing from cover at home is no use at the front. MASS and DEFEND
## leave bunkered units where they are.
func _launch(a_objective: Vector3) -> void:
	for squad: Squad in [_main, _reserve, _guard]:
		squad.clear()
	_main.add_all(_combat_units(_bot.get_units()))
	_main.policy = AssaultPolicy.new(
		_bot, _act, a_objective, _objective_entity, _objective_id, OBJECTIVE_EPSILON
	)
	_main.redirect()
	_act.evacuate(_bot.get_hosts_holding_my_units())


## Point the wave at `a_objective` again when it is no longer what the wave was sent at: a
## different believed structure, or the same belief drifted past OBJECTIVE_EPSILON from the
## point the wave holds. Compared with the WAVE'S point, not the last think's objective — the
## objective is re-read every think, so a creep of a few metres a think, or a new structure a
## short step on, never counted as a change, and the wave stood idle at a point whose target
## was gone. Only the wave is re-pointed; the reserve and guard keep their orders.
func _retarget_wave(a_objective: Vector3) -> void:
	var held: AssaultPolicy = _main.policy as AssaultPolicy
	if (
		held != null
		and held.target_id == _objective_id
		and held.point.distance_to(a_objective) <= OBJECTIVE_EPSILON
	):
		return
	_main.policy = AssaultPolicy.new(
		_bot, _act, a_objective, _objective_entity, _objective_id, OBJECTIVE_EPSILON
	)
	_main.redirect()


## MASS or DEFEND: the whole army is one body standing at `a_post`. A posture change is a
## real change even when the post has not moved, so the squad is told to re-issue to all.
func _hold(a_post: Vector3) -> void:
	_main.absorb(_reserve)
	_main.absorb(_guard)
	_main.add_all(_combat_units(_bot.get_units()))
	_main.policy = HoldPolicy.new(_act, a_post, OBJECTIVE_EPSILON)
	_main.redirect()


## ATTACK posture, nothing changed: a new combat unit joins the reserve (or the wave itself,
## under a cap of one); the reserve turns to a threatened structure when the cap allows a
## guard; and the reserve is released to the wave as a body when it is worth sending.
func _tick_reinforcements(a_objective: Vector3) -> void:
	var newcomers: Array = _combat_units(_bot.get_units()).filter(
		func(u: Actor) -> bool: return not (_main.has(u) or _reserve.has(u) or _guard.has(u))
	)
	if _may_run(2):
		_reserve.add_all(newcomers)
	else:
		_main.add_all(newcomers)
	_tick_guard()
	if _reserve.is_empty():
		return
	# The wave has nobody left: the reserve IS the army, and holding it back would leave the
	# objective to nobody.
	if _main.is_empty() or _value_of(_reserve.members()) >= reinforce_fraction * _wave_launch_value:
		_main.absorb(_reserve)
		return
	_reserve.policy = StagePolicy.new(_act, _staging_point(a_objective), OBJECTIVE_EPSILON)


## THE GUARD: while a wave is out and the base comes under threat, the staged reserve turns
## to the threatened structure instead of waiting to reinforce — the part of the army that
## is not committed answers the raid the wave's commitment used to leave unanswered. Only
## under a cap of three; it goes back to being the reserve once the threat has passed.
## Decided 2026-10-07; a fraction held home by rule is deliberately NOT a parameter.
func _tick_guard() -> void:
	if not _may_run(3):
		return
	var threats: Array = _base_threats()
	if threats.is_empty():
		_reserve.absorb(_guard)
		_guard.policy = null
		return
	var worst: Dictionary = threats[0]
	for threat: Dictionary in threats:
		if threat["value"] > worst["value"]:
			worst = threat
	# At the threat itself, not at the structure it is near: the guard is there to end it.
	_guard.policy = HoldPolicy.new(
		_act, (worst["enemy"] as Actor).global_position, OBJECTIVE_EPSILON
	)
	_size_guard(threats)


## Draw the guard from the guard and reserve together: the units best able to hurt the
## threats first, until their value against them reaches guard_strength_ratio × the threats'
## value. Whoever is not needed is the reserve, and goes on to the wave — so a threat that
## never ends no longer swallows everything built while it stands. A unit that cannot hurt
## any threat never guards. At least one unit answers any threat, however cheap.
func _size_guard(a_threats: Array) -> void:
	var needed: float = 0.0
	for threat: Dictionary in a_threats:
		needed += threat["value"]
	needed *= guard_strength_ratio
	var answers: Array = []  # [unit, its value against the threats]
	for unit: Actor in _guard.members() + _reserve.members():
		var best: float = 0.0
		for threat: Dictionary in a_threats:
			best = maxf(best, _bot.matchup(unit, threat["enemy"]))
		if best > 0.0:
			answers.append([unit, _bot.unit_cost(unit.id) * best])
	answers.sort_custom(
		func(a: Array, b: Array) -> bool:
			if a[1] != b[1]:
				return a[1] > b[1]
			return a[0].get_instance_id() < b[0].get_instance_id()
	)
	var chosen: Array = []
	var strength: float = 0.0
	for answer: Array in answers:
		if strength >= needed and not chosen.is_empty():
			break
		chosen.append(answer[0])
		strength += answer[1]
	var rest: Array = (_guard.members() + _reserve.members()).filter(
		func(unit: Actor) -> bool: return not chosen.has(unit)
	)
	_guard.set_members(chosen)
	_reserve.set_members(rest)


## Every threat to the base, at the radius this military judges one by — a command centre's
## under HEGEMONY, where it is the whole game, from further off (Bot.base_threats).
func _base_threats() -> Array:
	var centre_radius: float = defend_threat_radius
	if _bot.win_condition() == Scenario.WinCondition.HEGEMONY:
		centre_radius *= COMMAND_CENTRE_THREAT_MULTIPLIER
	return _bot.base_threats(defend_threat_radius, centre_radius)


## Whether the cap lets the military run `a_count` squads at once.
func _may_run(a_count: int) -> bool:
	return BotDifficulty.is_squad_uncapped(squad_cap) or squad_cap >= a_count


## A wave that has stood on its objective for OBJECTIVE_STALL_SECONDS with nobody fighting
## has found nothing there it can act on: abandon the objective for a while and let the next
## belief be chosen. The clock restarts whenever the wave is fighting (BotTargeting holds a
## member) or still travelling (its centroid is not yet near the objective).
func _check_objective_stall(a_objective: Vector3) -> void:
	var now: float = _bot.seconds_elapsed()
	if not claims.units_of(BotTargeting.CLAIM_OWNER).is_empty():
		_objective_since = now
		return
	if _main.is_empty():
		return
	if _main.centroid().distance_to(a_objective) > STALL_RADIUS:
		_objective_since = now
		return
	if now - _objective_since > OBJECTIVE_STALL_SECONDS:
		_abandon_objective(a_objective)


func _abandon_objective(a_position: Vector3) -> void:
	_abandoned_objectives.append(
		{"position": a_position, "until": _bot.seconds_elapsed() + OBJECTIVE_ABANDON_SECONDS}
	)
	_has_objective = false


## Whether `a_position` is within STALL_RADIUS of an objective abandoned and not yet expired.
## Expired entries are dropped as they are met.
func _is_abandoned(a_position: Vector3) -> bool:
	var now: float = _bot.seconds_elapsed()
	_abandoned_objectives = _abandoned_objectives.filter(
		func(entry: Dictionary) -> bool: return float(entry["until"]) > now
	)
	return _abandoned_objectives.any(
		func(entry: Dictionary) -> bool:
			return (entry["position"] as Vector3).distance_to(a_position) <= STALL_RADIUS
	)


## The bot's own command centre under threat, or null — only under HEGEMONY, where it is the
## first thing the army defends.
func _threatened_command_centre() -> Actor:
	if _bot.win_condition() != Scenario.WinCondition.HEGEMONY:
		return null
	return _bot.threatened_command_centre(defend_threat_radius * COMMAND_CENTRE_THREAT_MULTIPLIER)


## What `a_units` are worth, in the energy the wave's launch value is measured in.
func _value_of(a_units: Array) -> float:
	var total: float = 0.0
	for unit: Actor in a_units:
		total += float(_bot.unit_cost(unit.id))
	return total


## Where the reserve gathers while a wave is out: in front of the base, toward the objective.
func _staging_point(a_objective: Vector3) -> Vector3:
	var home: Vector3 = _home_anchor_position()
	var toward: Vector3 = a_objective - home
	if toward.length_squared() <= STAGING_OFFSET * STAGING_OFFSET:
		return home
	return _station_point(VU.in_xz(toward).normalized())


## WHERE THE ARMY STANDS when it is not marching: STAGING_OFFSET in front of the structure
## the enemy would reach first coming along `a_direction`. Both halves of "a good position"
## at once — next to the building that is exposed, on the side the threat comes from — and
## it is what replaced massing on the base centroid, which stood the army in the middle of
## its own buildings on whichever side they happened to be. Home itself with no structure.
func _station_point(a_direction: Vector2) -> Vector3:
	var home: Vector3 = _home_anchor_position()
	var front: Actor = _bot.frontmost_structure(a_direction)
	var anchor: Vector3 = front.global_position if front != null else home
	return anchor + VU.from_xz(a_direction) * STAGING_OFFSET


## Point every production structure's rally at `a_point`: re-issued to all of them when the
## point moves, and otherwise only to a structure that has no rally yet (one finished since).
## A new unit then walks to where the military wants it on its own, instead of standing at
## the door until the idle sweep finds it.
func _rally_production(a_point: Vector3, a_moved: bool) -> void:
	var moved: bool = a_moved or not _has_rally or _rally_point.distance_to(a_point) > RALLY_EPSILON
	_rally_point = a_point
	_has_rally = true
	var structures: Array = _bot.get_production_structures().filter(
		func(s: Actor) -> bool: return moved or s.rally_commands.is_empty()
	)
	if not structures.is_empty():
		_act.rally(structures, a_point)


func current_posture() -> Posture:
	return _posture


## Where the army is being sent, or null before the first think found anything to anchor on.
## An instrument for the decision simulations and the self-play harness; no manager reads it.
func current_objective() -> Variant:
	return _objective if _has_objective else null


## How many units are in the field with the current wave. An instrument for the self-play
## harness, which observes the bot and never issues; no manager reads it.
func wave_size() -> int:
	return _main.size() if _posture == Posture.ATTACK else 0


## How many combat units are held in reserve — not in the wave. Only meaningful in ATTACK
## posture; outside it every combat unit is "reserve" and the number is the army's size.
func reserve_size() -> int:
	return (
		_combat_units(_bot.get_units())
		. filter(
			func(u: Actor) -> bool: return not (_posture == Posture.ATTACK and _main.has(u))
		)
		. size()
	)


## How far ahead an army worth `a_own` is: its value over the smoothed enemy estimate, after
## the humility prior (assume the enemy is at least assumed_enemy_parity × our own unless more
## has been seen) and the floor.
func attack_ratio(a_own: float) -> float:
	var enemy_estimate: float = maxf(_enemy_value_estimate, a_own * assumed_enemy_parity)
	return a_own / maxf(enemy_estimate, ENEMY_VALUE_FLOOR)


## The value ratio a wave must clear to launch: attack_value_ratio, relaxed by the stalemate
## clock and never below MIN_ATTACK_RATIO.
func required_attack_ratio() -> float:
	return maxf(
		MIN_ATTACK_RATIO, attack_value_ratio - _stalemate_time * STALEMATE_ESCALATION_PER_SEC
	)


## The wave and objective state no other accessor reports, for the debug overlay. Times are
## seconds; `objective_entity` is null or possibly freed, so a reader checks it is valid.
func debug_state() -> Dictionary:
	var now: float = _bot.seconds_elapsed()
	return {
		"objective_entity": _objective_entity,
		"wave_active": _wave_active,
		"wave_launch_value": _wave_launch_value,
		"wave_value": _value_of(_main.members()) if _wave_active else 0.0,
		"regroup_left": maxf(0.0, _regroup_until - now),
		"on_objective": now - _objective_since if _has_objective else 0.0,
		"stalemate": _stalemate_time,
		"enemy_estimate": _enemy_value_estimate,
		"abandoned_objectives": _abandoned_objectives.duplicate(),
		"rally": _rally_point if _has_rally else null,
	}


## The army's squads — main, reserve, guard — for the harness and the decision simulations.
func squads() -> Array:
	return [_main, _reserve, _guard]


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
	if _bot.is_base_under_threat(defend_threat_radius) or _threatened_command_centre() != null:
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
	# Judged on the WAVE, not the army: a reserve or guard at home is not the wave holding up,
	# and counting them kept a wave of two "unspent" while a guard grew behind it.
	if _wave_active:
		var wave: float = _value_of(_main.members())
		if wave <= _wave_launch_value * WAVE_SPENT_FRACTION or _should_abort_wave(wave):
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

	var ratio: float = attack_ratio(own)
	# Bar starts at attack_value_ratio and relaxes the longer we hold without fighting, so a
	# parity deadlock eventually forces a commit (but never below MIN_ATTACK_RATIO).
	var threshold: float = required_attack_ratio()

	if ratio >= threshold:
		_wave_active = true
		# What _launch is about to send, so the spent test compares the wave with itself.
		_wave_launch_value = _value_of(_combat_units(_bot.get_units()))
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
	return a_units.filter(_is_armys)


## Whether `a_unit` is the army's to order right now — see _combat_units. Also every squad's
## `eligible` test, so a member claimed mid-fight or on an errand is left alone by dispatch
## and picked up again when released.
func _is_armys(a_unit: Actor) -> bool:
	return (
		_bot.unit_has_combat_utility(a_unit)
		and not claims.is_claimed(a_unit)
		and not BotEconomy._is_constructing(a_unit)
		and not BotOpportunist.is_committed(a_unit)
		and not _bot.is_suicide_aoe_unit(a_unit)
	)  # kamikazes are micro'd by BotKamikaze


## The world position to rally on for `posture`, or null when none applies.
func _objective_for(a_posture: Posture) -> Variant:
	match a_posture:
		Posture.DEFEND:
			# The command centre first, under HEGEMONY: losing it is losing the match, so it
			# outranks a more damaged building elsewhere.
			var centre: Actor = _threatened_command_centre()
			if centre != null:
				return centre.global_position
			var threatened: Actor = _bot.most_threatened_structure()
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
			# …AND REACHABLE, and not lately abandoned. A belief across a cliff is one the
			# walk can never disprove (nobody gets vision of it), so the army would stand
			# beside it for the rest of the match; the stall rule catches what the path
			# query does not.
			var origin: Vector3 = _home_anchor_position()
			var actionable: Callable = func(entry: CommanderBlackboard.Entry) -> bool:
				return (
					Bot.any_unit_can_damage(army, entry.entity)
					and not _bot.belief_is_disproved(entry)
					and not _is_abandoned(entry.last_known_location)
					and _bot.is_reachable(origin, entry.last_known_location, REACH_TOLERANCE)
				)
			# Under HEGEMONY the enemy's COMMAND CENTRE is the objective whenever one is
			# believed and actionable: taking it is the whole match. WHEN to go is still the
			# commit gates' decision (_committing_to_attack), which is what keeps this from being
			# a blind beeline — a centre tough enough that the army dies before it does makes
			# the wave a premature commitment the value gate refuses; a centre that is not, the
			# bot snipes. That tuning is the content's (objectives-and-completion.md §Win
			# conditions), not the bot's.
			_objective_entity = null
			_objective_id = 0
			if _bot.win_condition() == Scenario.WinCondition.HEGEMONY:
				var centre_actionable: Callable = func(entry: CommanderBlackboard.Entry) -> bool:
					return _bot.is_command_centre_type(entry.type) and actionable.call(entry)
				var centre: CommanderBlackboard.Entry = _bot.nearest_believed_enemy_structure_entry(
					centre_actionable
				)
				if centre != null:
					_objective_entity = centre.entity
					_objective_id = centre.instance_id
					return centre.last_known_location
			var believed: CommanderBlackboard.Entry = _bot.nearest_believed_enemy_structure_entry(
				actionable
			)
			if believed != null:
				_objective_entity = believed.entity
				_objective_id = believed.instance_id
				return believed.last_known_location
			# Nothing of theirs standing that we know of: go after the last place we saw a unit.
			return _bot.nearest_believed_enemy_unit_position(_home_anchor_position(), actionable)
		_:  # MASS
			# Not the base centroid: the army waits on the threat side of the base, in front
			# of the building the enemy reaches first (Bot.threat_direction is fog-limited and
			# falls back to the map's middle, so an unscouted bot still faces outward).
			if _home_anchor() == null:
				return null
			return _station_point(_bot.threat_direction(VU.in_xz(_home_anchor_position())))


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
