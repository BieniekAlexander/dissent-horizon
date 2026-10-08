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
## Four signals are registered by default (threat, matchup effectiveness, finishability,
## proximity) and the mix is purely additive: append_signal(weight, fn) adds another, and a
## per-difficulty config can hand BotTargeting a different mix + margin + scan radius without
## changing this logic. Only `switch_margin` is a difficulty parameter today; the WEIGHTS are
## not, and they are a natural thing for the self-play harness to search.

## How far (world units) a unit notices threats worth reacting to.
const DEFAULT_SCAN_RADIUS: float = 8.0

## What running a target over scores on the EFFECTIVENESS signal, whose scale is the damage
## multiplier a weapon gets (1.0 neutral, a dedicated counter above it). A crush is a kill on
## contact — the "damage per shot" is the whole target — so it sits above a counter's
## multiplier, and below the point where a crusher would leave a fight it can win with a gun
## to chase infantry across the field (the proximity and threat signals still decide that).
## Decided 2026-10-07 (ontology.md §Affordances, "Crush is lethality"); tune in testing.
const CRUSH_EFFECTIVENESS_SIGNAL: float = 2.0

## THE TWO GATES ON A RUN-OVER (Alex, 2026-10-07): it is a good decision when the enemies can
## be crushed, there are FEW ENOUGH that the crusher will not be killed on the way, and they
## are CLUMPED. Both are read off what the unit can see now; the threat field will replace the
## first (world-model.md §L2).
##
## Survivable: the damage the visible enemies that can shoot the crusher would deal during the
## drive — their sustained dps summed, times the time to contact — may be at most this fraction
## of the crusher's CURRENT hp. A drive that would cost more is a drive into a death, and the
## unit shoots or leaves instead.
const RUN_OVER_MAX_HP_SPENT: float = 0.5
## Clumped: each further crushable within this of the target adds CRUSH_CLUMP_BONUS to the
## run-over's effectiveness, so a target standing in a knot of infantry outranks a lone one —
## the drive-through takes the knot. One body width or so.
const CRUSH_CLUMP_RADIUS: float = 2.0
const CRUSH_CLUMP_BONUS: float = 0.5
const CRUSH_CLUMP_MAX_BONUS: float = 2.0

## The visible enemies the current pick was drawn from, for the clump reading inside the
## static effectiveness signal. Set per _retarget; framework-shaped scratch rather than state.
static var _scan_nearby: Array = []

var _bot: Bot
var _act: BotActuator

## Active scoring signals: each {weight: float, fn: Callable(unit, candidate) -> float}.
var _signals: Array = []
## A candidate must beat the current target's score by this factor to be worth
## switching to. > 1.0. Higher = more committed (and less twitchy / less optimal).
var switch_margin: float = 1.3
var scan_radius: float = DEFAULT_SCAN_RADIUS

## Default per-signal weights (the relative importance dial). Each signal is roughly
## normalised so the weights are comparable: threat 0/1, effectiveness ~a damage multiplier
## centred on 1, finishability 0..1, proximity 0..1.
##
## Three of the four are PARAMETERS now (BotDifficulty.retarget_weight_*, applied through
## set_signal_weights). THREAT deliberately is not: the score is only ever compared against
## the current target's score times `switch_margin`, so scaling every weight by the same
## factor changes no decision, and one of the four has to be the ruler the others are
## measured with. Searching all four would waste a dimension on that free scale.
const W_THREAT: float = 1.0
const W_EFFECTIVENESS: float = 1.0
const W_FINISHABILITY: float = 1.0
const W_PROXIMITY: float = 0.5

## The owner name this module claims units under (BotClaims): a unit it has sent at a
## specific target is engaged, and the army's rally must not override it mid-fight.
const CLAIM_OWNER: StringName = &"targeting"

## Which manager owns which unit; the brain replaces this with the bot's shared registry. A
## fresh one by default, so a bare manager in a test sees every unit unclaimed.
var claims: BotClaims = BotClaims.new()

## Work units per unit looked at, and per candidate target scored for it (BotScheduler counts
## work in units of roughly a microsecond on the calibration machine).
const UNIT_WORK_UNITS: int = 25
const CANDIDATE_WORK_UNITS: int = 20

## Work spent by the current tick, accumulated by _retarget. Reset at the top of each tick.
var _work: int = 0


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
func append_signal(a_weight: float, a_fn: Callable) -> void:
	_signals.append({"weight": a_weight, "fn": a_fn})


## Re-weight the three searchable signals of the default mix (see BotDifficulty.
## retarget_weight_*). Matched by the signal's own function rather than by position, so an
## extra signal appended by a caller keeps its weight and the order of registration does not
## become load-bearing. Threat keeps W_THREAT: it is the scale the other three are read
## against, and the comparison is invariant to that scale.
func set_signal_weights(a_effectiveness: float, a_finishability: float, a_proximity: float) -> void:
	var applied: int = 0
	for sig: Dictionary in _signals:
		match (sig["fn"] as Callable).get_method():
			&"effectiveness_signal":
				sig["weight"] = a_effectiveness
				applied += 1
			&"finishability_signal":
				sig["weight"] = a_finishability
				applied += 1
			&"proximity_signal":
				sig["weight"] = a_proximity
				applied += 1
	# A knob that silently does nothing is worse than one that is missing: every default here
	# equals the constant it replaced, so a match that stopped resolving would leave the mix
	# looking right and the parameter dead, with no test able to see it. Say so instead.
	if applied < 3:
		push_warning("BotTargeting.set_signal_weights matched %d of 3 default signals" % applied)


## Returns the work units spent.
func tick() -> int:
	_work = 0
	_release_finished_engagements()
	for unit: Actor in _bot.get_units():
		_work += UNIT_WORK_UNITS
		if not claims.can_claim(unit, CLAIM_OWNER, BotClaims.Priority.COMBAT):
			continue  # an errand or an exclusive owner has it
		if unit.weapon_inventory == null and not _can_run_over(unit):
			continue  # can neither shoot nor run anything over
		if BotEconomy._is_constructing(unit):
			continue  # don't yank the active builder mid-construction
		if BotOpportunist.is_committed(unit):
			continue  # don't yank a unit mid-liberation (or other committed opportunity)
		if _bot.is_suicide_aoe_unit(unit):
			continue  # kamikazes are micro'd by BotKamikaze (cost-effective blasts only)
		_retarget(unit)
	return _work


## Give back every unit whose engagement is over — its Attack or run-over ended, or
## something stronger replaced it — so the army can rally it again.
func _release_finished_engagements() -> void:
	for unit: Variant in claims.units_of(CLAIM_OWNER):
		if not is_instance_valid(unit):
			claims.release(unit, CLAIM_OWNER)
			continue
		var engaged: Actor = unit as Actor
		var command: MoveCommand = engaged.current_command()
		if not (command is Attack or _is_run_over(engaged, command)):
			claims.release(unit, CLAIM_OWNER)


func _retarget(a_unit: Actor) -> void:
	# Candidates: enemies within this unit's OWN aggro range that it can attack.
	# Scoping to aggro range (not a fixed scan radius) keeps picks inside the
	# persist=false attack leash, so the chosen target sticks instead of being
	# instantly dropped as out-of-range and re-picked every think.
	# The scan is a sphere about the unit's centre, so it is grown by the unit's own extent and
	# the footprint gap then decides, as for every range (SU.hull_gap).
	var radius: float = _engage_radius(a_unit)
	var from: Hull = a_unit.hull()
	var nearby: Array = _bot.visible_enemies_near(a_unit.global_position, radius + from.extent())
	var candidates: Array = nearby.filter(
		func(c: Actor): return _can_engage(a_unit, c) and Hull.gap(from, c.hull()) <= radius
	)
	# The signals are static (unit, candidate) functions; the clump reading needs the scan
	# they were drawn from, handed over through this scratch for the duration of the pick and
	# cleared after it, so it never holds a reference past the tick that made it.
	_scan_nearby = nearby
	_work += candidates.size() * CANDIDATE_WORK_UNITS
	if candidates.is_empty():
		_scan_nearby = []
		return
	var current: Actor = _current_target(a_unit)
	var best: Actor = _best_candidate(a_unit, current, candidates)
	_scan_nearby = []
	# The piece this unit should be on: a better candidate, else the one it is on already.
	var chosen: Actor = best if best != null else current
	if chosen == null or not chosen.is_inside_tree():
		return  # nothing to be on, or the current target is garrisoned
	if Bot.crushes(a_unit.movement, chosen) and _run_over_is_survivable(a_unit, chosen, nearby):
		# A RUN-OVER, whether or not the unit could also shoot it: a crush is a kill on
		# contact, and a gun that can merely target the piece is the slower way to the same
		# end — which is why a crushable target the unit is already SHOOTING (an Attack its
		# own aggro picked) is converted too. The controls' own follow order, which the crush
		# mechanic completes on contact; it ends by itself when the target is taken (captured
		# off the tree) or dies, and the military re-tasks the unit once it goes idle.
		if chosen == current and _is_run_over(a_unit, a_unit.current_command()):
			return  # already running it over
		_act.move_at([a_unit], chosen)
		claims.claim(a_unit, CLAIM_OWNER, BotClaims.Priority.COMBAT)
	elif best != null and best != current:
		# persist=false: deal with the threat, then fall back to the army objective
		# (the military manager re-tasks the unit once it goes idle).
		_act.attack([a_unit], best, false)
		claims.claim(a_unit, CLAIM_OWNER, BotClaims.Priority.COMBAT)


## Whether `a_unit` has a weapon that can be brought to bear on `a_candidate`.
static func _can_shoot(a_unit: Actor, a_candidate: Actor) -> bool:
	return (
		a_unit.weapon_inventory != null
		and a_unit.weapon_inventory.weapon_for_target(a_candidate) != null
	)


## Whether `a_unit` can hurt `a_candidate` by any means it has: a weapon, or driving over it.
## Crush is lethality (ontology.md §Affordances), so a crusher is retargeted like a shooter.
static func _can_engage(a_unit: Actor, a_candidate: Actor) -> bool:
	return _can_shoot(a_unit, a_candidate) or Bot.crushes(a_unit.movement, a_candidate)


## Whether `a_unit` outranks SOME crush class — there is something it could run over.
static func _can_run_over(a_unit: Actor) -> bool:
	return a_unit.movement != null and a_unit.movement.can_crush_anything()


## The first gate: would `a_unit` reach `a_target` with RUN_OVER_MAX_HP_SPENT of its hp or
## less spent on the way? `a_nearby` is the visible enemy set the candidates were drawn from;
## the ones that can shoot the crusher are the ones that will.
static func _run_over_is_survivable(
	a_unit: Actor, a_target: Actor, a_nearby: Array
) -> bool:
	if a_unit.defense == null or a_unit.defense.hp <= 0.0:
		return false
	var speed: float = a_unit.movement.effective_max_speed() if a_unit.movement != null else 0.0
	if speed <= 0.0:
		return false
	var seconds_to_contact: float = (
		VU.in_xz(a_unit.global_position).distance_to(VU.in_xz(a_target.global_position)) / speed
	)
	var incoming_dps: float = 0.0
	for enemy: Actor in a_nearby:
		if enemy.weapon_inventory == null:
			continue
		var weapon: Weapon = enemy.weapon_inventory.weapon_for_target(a_unit)
		if weapon != null:
			incoming_dps += weapon.approximate_dps()
	return incoming_dps * seconds_to_contact <= RUN_OVER_MAX_HP_SPENT * a_unit.defense.hp


## The second gate's reading: how many OTHER crushables stand within CRUSH_CLUMP_RADIUS of
## `a_target` — what the drive-through would take with it.
static func _clump_around(a_unit: Actor, a_target: Actor, a_nearby: Array) -> int:
	var knot: int = 0
	var at: Vector2 = VU.in_xz(a_target.global_position)
	# Untyped: the scratch may hold a piece freed since the scan (CLAUDE.md §A freed object
	# cannot be passed to a typed parameter), and the loop variable is one.
	for other: Variant in a_nearby:
		if not is_instance_valid(other) or other == a_target:
			continue
		var piece: Actor = other as Actor
		if piece == null or not Bot.crushes(a_unit.movement, piece):
			continue
		if VU.in_xz(piece.global_position).distance_to(at) <= CRUSH_CLUMP_RADIUS:
			knot += 1
	return knot


## Whether `a_command` is a run-over `a_unit` is on: a plain Move (not an AttackMove, which
## extends it) aimed at a piece the unit would crush.
static func _is_run_over(a_unit: Actor, a_command: MoveCommand) -> bool:
	if a_command == null or a_command.get_script() != MoveCommand or a_command.message == null:
		return false
	var target: Variant = a_command.message.target
	if target == null or not is_instance_valid(target) or not (target is Actor):
		return false
	return Bot.crushes(a_unit.movement, target as Actor)


## HOW FAR THIS UNIT LOOKS FOR A BETTER TARGET: the further of its aggro shape and the
## longest weapon it carries, falling back to scan_radius when it has neither.
##
## It used to be the aggro shape ALONE, and on this content the aggro shapes are authored
## TIGHTER than the weapons — a Badger aggros at 2 world units and shoots at 5. That is what
## made a self-play match unwinnable: BotMilitary marches the army onto the nearest enemy
## structure, `nearest_navmesh_point` puts it a few units short of the footprint (a building
## blocks the navmesh it is standing on), the AttackMove completes there, and nothing —
## neither idle aggro nor this scan — could see a building the army was already in range to
## destroy. Every unit then idled at the foot of the base for the rest of the match.
##
## REACH is also the honest bound for the leash the pick is made under: `_retarget` issues a
## persist=false Attack, which is dropped when the target leaves WEAPON range, so scanning
## to weapon range picks exactly the targets that will stick. Scanning to the aggro shape
## was the narrower of the two bounds for no reason but that it was the one already written.
func _engage_radius(a_unit: Actor) -> float:
	var radius: float = maxf(_aggro_radius(a_unit), _weapon_reach(a_unit))
	return radius if radius > 0.0 else scan_radius


## XZ radius of `a_unit`'s wider aggro volume, or 0.0 when it has none.
func _aggro_radius(a_unit: Actor) -> float:
	return maxf(0.0, a_unit.aggro_radius())


## The longest reach among `a_unit`'s weapons, in world units, or 0.0 when it is unarmed.
## Ground reach: the candidate set is not known yet at this point, and every range shape is
## authored as one very tall cylinder, so the ground shape is the representative one.
func _weapon_reach(a_unit: Actor) -> float:
	if a_unit.weapon_inventory == null:
		return 0.0
	var reach: float = 0.0
	for w: Weapon in a_unit.weapon_inventory.get_weapons():
		reach = maxf(reach, w.ground_reach())
	return reach


## Every unit this manager holds in a fight, with the enemy it is set on: [{"unit", "target"}].
## A held unit between orders has no target and is left out. For the debug overlay.
func engagements() -> Array:
	var out: Array = []
	for unit: Variant in claims.units_of(CLAIM_OWNER):
		if not is_instance_valid(unit):
			continue
		var target: Actor = _current_target(unit)
		if target != null:
			out.append({"unit": unit, "target": target})
	return out


## The enemy this unit is presently set to attack or run over, or null (e.g. while
## attack-moving).
func _current_target(a_unit: Actor) -> Actor:
	if not a_unit.has_command():
		return null
	var command: MoveCommand = a_unit.current_command()
	if command is Attack or _is_run_over(a_unit, command):
		var t: Entity = command.message.target
		if is_instance_valid(t):
			return t as Actor
	return null


## Highest-scoring candidate that clears the commitment margin over the current
## target, or null to keep the current target. A null current target (attack-moving)
## means any positively-scored candidate qualifies.
func _best_candidate(
	a_unit: Actor, a_current: Actor, a_candidates: Array
) -> Actor:
	var threshold: float = _score(a_unit, a_current) * switch_margin if a_current != null else 0.0
	var best: Actor = null
	var best_score: float = threshold
	for c: Actor in a_candidates:
		var s: float = _score(a_unit, c)
		if s > best_score:
			best_score = s
			best = c
	return best


func _score(a_unit: Actor, a_candidate: Actor) -> float:
	# Off the tree is garrisoned: held, not gone, and no more engageable than a dead piece.
	if (
		a_candidate == null
		or not is_instance_valid(a_candidate)
		or not a_candidate.is_inside_tree()
	):
		return 0.0
	var total: float = 0.0
	for sig: Dictionary in _signals:
		total += sig["weight"] * (sig["fn"] as Callable).call(a_unit, a_candidate)
	return total


# ─── SIGNALS ────────────────────────────────────────────────────────────────
# Each signal is static, (unit, candidate) -> float, higher = more desirable to
# attack. Keep them cheap (they run per unit per candidate per think).


## THREAT — does `candidate` pose a present danger to `unit`: it can target `unit`
## AND is currently positioned to hit it. A harmless target (a building, or an enemy
## out of its own range) scores 0. Binary (1.0 = a live threat), so combined with the
## commit margin it means "drop a non-threat for any threat, then stay on it."
static func threat_signal(unit: Actor, candidate: Actor) -> float:
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
static func effectiveness_signal(unit: Actor, candidate: Actor) -> float:
	# Hand-set matchup override wins over the computed multiplier (parity with the
	# production effectiveness in Bot.unit_effectiveness_vs).
	var override: Variant = DamageTable.matchup_override(unit.id, candidate.id)
	if override != null:
		return override
	# A crush is a kill on contact, and outranks any shot the unit could take instead; a
	# target in a knot of crushables is worth the knot (the second run-over gate).
	if Bot.crushes(unit.movement, candidate):
		var knot: int = _clump_around(unit, candidate, _scan_nearby)
		return CRUSH_EFFECTIVENESS_SIGNAL + minf(CRUSH_CLUMP_MAX_BONUS, knot * CRUSH_CLUMP_BONUS)
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
static func finishability_signal(_unit: Actor, candidate: Actor) -> float:
	var d: Defense = candidate.defense
	if d == null or d.hp_max <= 0.0:
		return 0.0
	return clampf(1.0 - d.hp / d.hp_max, 0.0, 1.0)


## PROXIMITY — prefer closer targets (less travel, faster to engage). Decreasing with
## XZ distance, self-normalising to (0, 1] (1 when adjacent, → 0 far away).
static func proximity_signal(unit: Actor, candidate: Actor) -> float:
	var dist: float = VU.in_xz(unit.global_position).distance_to(
		VU.in_xz(candidate.global_position)
	)
	return 1.0 / (1.0 + dist)
