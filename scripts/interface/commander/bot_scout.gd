class_name BotScout
extends RefCounted

## BotScout — maintains a fog-of-uncertainty grid and tasks the unit best SUITED to
## scouting (see _scout_score) to visit unseen / stale grid points continuously.
##
## The scout grid divides the map into SCOUT_GRID_SIZE-world-unit intervals.
## Each point carries a timestamp (Bot.seconds_elapsed()) of when it was last
## in line-of-sight of an owned unit. A point is "expired" once that timestamp
## is more than SCOUT_EXPIRATION_TIMER seconds in the past.
##
## Scouts are claimed one at a time, up to `unit_budget`, and only while a further one is
## worth its absence (_scouting_is_worth_it); each is then dispatched on the ERRAND with the
## best expected return (_next_scout_point). A claim is HELD across a re-task by another
## manager and given up only for a real errand or once the absence stops paying — see
## _update_scouts.

## World units between scout grid columns/rows.
const SCOUT_GRID_SIZE: int = 5
## Seconds before a scouted point is considered expired and worth revisiting.
const SCOUT_EXPIRATION_TIMER: float = 60.0

## Scout-suitability weights — see _scout_score for what each term means and why the
## numbers are not to be balanced against. Speed and vision are what a scout is FOR, so
## they carry the full weight; replacement cost is a risk discount rather than a purpose,
## so it carries half; and one live responsibility is set to outweigh a full advantage in
## either purpose, because a unit that is needed elsewhere is needed elsewhere.
const W_SPEED: float = 1.0
const W_VISION: float = 1.0
const W_REPLACEMENT_ENERGY: float = 0.5
const W_REPLACEMENT_TIME: float = 0.5
const W_RESPONSIBILITY: float = 1.5

## WHAT KNOWING THE WHOLE MAP IS WORTH, in energy — the authored constant that lets
## information be compared against everything else the bot could do with a unit. It is the
## one figure in the bot that cannot be derived from the game's own numbers, and it is
## deliberately a single named value rather than a rate hidden in a formula: it is the price
## of information, and it should be arguable in one line.
##
## PLACEHOLDER. Roughly two units' worth, which says a bot that can see everything is
## better off than one that is two units richer and blind.
const INFORMATION_VALUE_ENERGY: float = 400.0

## HOW MUCH OF THE ENEMY-LIKELIHOOD WEIGHT A POINT KEEPS AT THE BOT'S OWN FRONT DOOR.
## _enemy_prior runs from this at home to 1.0 at the far edge of the map. It is a floor
## rather than a zero because the bot still has to notice something walking up its own drive,
## and it is low because the whole point of the term is that the opponent is somewhere else.
##
## A PLACEHOLDER on the same footing as the scoring weights below: the shape is settled, the
## number is what the self-play harness exists to search.
const HOME_PRIOR_FLOOR: float = 0.1

## Ceiling on how many points along a candidate errand are sampled to estimate how dark the
## corridor is (_expected_sightings). The path is sampled at grid-interval spacing up to this
## many; a walk across the whole map is then estimated from a dozen readings rather than from
## a hundred, which is the difference between an estimate and a sweep.
const MAX_PATH_SAMPLES: int = 12

## The fraction of a scout's own price the bot expects to forfeit by sending it away —
## partly the risk of losing it alone, partly the army being down a unit while it is gone.
## This is what makes scouting with something expensive a real cost rather than a free move.
const ABSENCE_RISK: float = 0.5

var _bot: Bot
var _act: BotActuator

## The bot's own seeded stream (BotBrain.rng), for which unit scouts; null makes it the
## sort it was. The DESTINATION is not sampled: that search is a resumable sweep keeping one
## running best, and sampling it would mean keeping every point's score. TODO.
var rng: RandomNumberGenerator = null
## How willing the scout choice is to send a near-best candidate (BotDifficulty).
var decision_temperature: float = 0.0

## Vector2i → float: seconds_elapsed() when the point was last observed.
## All points start at -(SCOUT_EXPIRATION_TIMER + 1.0) — treated as never scouted.
var _scout_grid: Dictionary = {}

## Vector2i → true for every point that has been in sight at least once
## (set only on a genuine LOS hit, never by the optimistic waypoint stamp). Drives the
## coverage query so a scenario can assert the whole map was actually scouted.
var _ever_seen: Dictionary = {}

## Precomputed world-space position (with terrain Y) for each grid index.
## Built once in _init; avoids recomputing per tick.
var _scout_grid_positions: Dictionary = {}

## The map's transform, inverted, cached at grid-build time: _grid_index_at runs it over
## every sampled point of every candidate errand, and Transform3D.affine_inverse() is not
## something to recompute a few thousand times per dispatch. IDENTITY when there is no map,
## which is also what makes the selector exercisable against a synthetic grid.
var _map_inverse: Transform3D = Transform3D.IDENTITY

## Map half-extents in local space, cached for _grid_world_pos.
var _map_half_w: float = 0.0
var _map_half_d: float = 0.0
## Full local-space extents (= world-space extents when Map scale = 1).
var _map_width: float = 0.0
var _map_depth: float = 0.0

## CEILING on how many units may be away scouting at once — no longer the decision itself.
## 0 means the bot never scouts and plays on belief alone, the handicap an easy bot gets
## (BotDifficulty.scout_unit_budget). Whether the bot uses the whole allowance is decided
## per unit by _scouting_is_worth_it: a cap says what is permitted, not what is wise.
var unit_budget: int = 1

## The units currently out scouting. Several, because "how many should scout" is a
## trade-off rather than a constant (the user's own framing: n = infinity is obviously
## ideal, so the question is what each extra scout costs).
var _scouts: Array = []

## HOW LONG A SCOUT MAY MAKE NO GROUND before its waypoint is written off as unreachable.
##
## A scout is only ever handed its NEXT waypoint when it goes idle, and a Move command that
## can never arrive never goes idle — so one unreachable point parked a scout permanently
## and froze the bot's map knowledge with it. Measured on a 20-minute self-play match:
## `observed_fraction` stopped at 0.28 and 0.15 for the two bots and did not move again for
## twelve simulated minutes, with the scout alive, un-retasked, and standing 1.4 world units
## from a destination it never reached (gdd/systems/ai/bot-engagement-fixes.md).
##
## Deliberately a distance-over-time test rather than a plain timer: a long walk across the
## map is not a stall, and a timer sized to allow it would be too slow to catch one.
const SCOUT_STALL_SECONDS: float = 12.0
## How far a scout must get in SCOUT_STALL_SECONDS to count as making progress. Roughly two
## grid intervals of slack, so ordinary path wiggle and obstacle avoidance never read as stuck.
const SCOUT_STALL_DISTANCE: float = 2.0

## Per scout (by instance id): { "at": Vector3, "since": float, "goal": Variant } — where it
## was when it last made progress, and when, and the waypoint it was last sent to (null before
## its first). The goal is kept because nothing else records the errand: the unit's own order
## may since have been replaced by a manager that borrowed it. Keyed by id rather than by the
## node so a freed scout's entry can be pruned without touching a dangling reference.
var _scout_progress: Dictionary = {}

## Vision-window offsets by radius in grid steps, built on demand — see _vision_window.
var _window_cache: Dictionary = {}

## The owner name this module claims scouts under (BotClaims).
const CLAIM_OWNER: StringName = &"scout"

## Which manager owns which unit; the brain replaces this with the bot's shared registry. A
## fresh one by default, so a bare BotScout in a test sees every unit unclaimed.
var claims: BotClaims = BotClaims.new()

## Work-unit costs of the sight sweep (BotScheduler counts work in units of roughly a
## microsecond on the calibration machine). A point inside a unit's window costs a distance
## test; one inside its vision costs a fog pixel read on top.
const SIGHT_POINT_WORK_UNITS: int = 1
const SIGHT_FOG_READ_WORK_UNITS: int = 1

## The sight sweep in progress: the units still to look through, and how far it has got. A
## resumable sweep's cursor (see BotJob) — state because the sweep is split across ticks, and
## what it walks has to survive between them. Entries are untyped because a unit can be freed
## while it waits.
var _sight_queue: Array = []
var _sight_cursor: int = 0

## Work units spent by the current dispatch pass, accumulated by the helpers it calls so none of
## them has to thread a count back through its return value. Reset at the top of each pass.
var _work: int = 0

## Scouts waiting for a waypoint, in the order they asked, and the errand search being run for
## the first of them. A resumable sweep's cursor (see BotJob): scoring every grid point for one
## dispatch cost tens of milliseconds on a large map, so a dispatch may span several ticks.
## Entries are untyped because a scout can be freed while it waits.
var _dispatch_queue: Array = []
## The search in progress for the head of _dispatch_queue (see _start_errand_search), or empty.
var _errand: Dictionary = {}
## Work-unit costs of dispatching: weighing one candidate unit, and scoring one grid point as an
## errand (a window count plus a sampled corridor).
const CANDIDATE_WORK_UNITS: int = 9
const ERRAND_POINT_WORK_UNITS: int = 13


func _init(a_bot: Bot, a_act: BotActuator) -> void:
	_bot = a_bot
	_act = a_act
	_build_scout_grid()


## Dispatch: claim, keep or release scouts and hand out waypoints, spending about
## `a_allowance` work units; a dispatch that runs out resumes on the next call
## (is_dispatch_pending) before anything is decided afresh. Returns the work units spent. What
## has been SEEN is updated separately, by sweep_sight.
func tick(a_allowance: int = BotJob.UNLIMITED_WORK_UNITS) -> int:
	if is_dispatch_pending():
		_work = 0
		_drain_dispatch(a_allowance)
		return _work
	return _update_scouts(a_allowance)


## True while a scout is still waiting for the waypoint a dispatch pass decided to give it.
func is_dispatch_pending() -> bool:
	return not _dispatch_queue.is_empty()


## Mark every scout-grid point an owned unit can see, spending at most about `a_allowance`
## work units and resuming where it stopped on the next call (is_sight_pending). A pass starts
## by taking the current unit list; units that die during it are skipped.
func sweep_sight(a_allowance: int) -> int:
	if _bot.map == null:
		return 0
	if _sight_cursor >= _sight_queue.size():
		_sight_queue = _bot.get_units()
		_sight_cursor = 0
	var spent: int = 0
	while _sight_cursor < _sight_queue.size() and spent < a_allowance:
		var unit: Variant = _sight_queue[_sight_cursor]
		_sight_cursor += 1
		if is_instance_valid(unit) and (unit as Node).is_inside_tree():
			spent += _mark_seen_by(unit)
	return spent


## True while a sight pass is part-way through its unit list.
func is_sight_pending() -> bool:
	return _sight_cursor < _sight_queue.size()


# ─── COVERAGE QUERY (used by scenario tests / debug) ─────────────────────────


## Number of scout-grid points that have been in sight at least once.
func observed_point_count() -> int:
	return _ever_seen.size()


## Total number of scout-grid points.
func total_point_count() -> int:
	return _scout_grid.size()


## Fraction (0–1) of scout-grid points seen at least once; 0 when the grid is empty.
func observed_fraction() -> float:
	if _scout_grid.is_empty():
		return 0.0
	return float(_ever_seen.size()) / float(_scout_grid.size())


## Where a REVEAL (a Scan) is best spent: the grid point that is NOT currently scouted —
## never seen, or seen longer ago than SCOUT_EXPIRATION_TIMER, and not in the bot's vision
## right now — nearest to `a_toward`, as a world position; null when every point is
## scouted. Nearest to where the enemy is believed to be, because that is the ground a scout
## would be sent to and cannot survive on. The live-vision test is what stops a second Scan
## landing where the first one's permanent observer still stands once its stamp has expired
## (measured: a repeat fraction of 0.47 with the stamp alone).
func reveal_point(a_toward: Vector2) -> Variant:
	var threshold: float = _bot.seconds_elapsed() - SCOUT_EXPIRATION_TIMER
	var sees: bool = _bot.has_fog()
	var best: Variant = null
	var best_distance: float = INF
	for idx: Vector2i in _scout_grid:
		if float(_scout_grid[idx]) >= threshold:
			continue
		var position: Vector3 = _scout_grid_positions[idx]
		if sees and _bot.has_vision_at(position):
			continue
		var distance: float = VU.in_xz(position).distance_squared_to(a_toward)
		if distance < best_distance:
			best_distance = distance
			best = position
	return best


## Stamp every grid point within `a_radius` of `a_centre` as seen now. A Scan's observer is
## uncommandable and so never walks the sight pass above; without this the next Scan would be
## aimed at the ground the last one is already watching.
func mark_revealed(a_centre: Vector3, a_radius: float) -> void:
	var now: float = _bot.seconds_elapsed()
	var centre: Vector2 = VU.in_xz(a_centre)
	var radius_sq: float = a_radius * a_radius
	for idx: Vector2i in _scout_grid_positions:
		if VU.in_xz(_scout_grid_positions[idx]).distance_squared_to(centre) <= radius_sq:
			_scout_grid[idx] = now
			_ever_seen[idx] = true


## True once every scout-grid point has been in sight at least once.
func all_points_seen() -> bool:
	return not _scout_grid.is_empty() and _ever_seen.size() >= _scout_grid.size()


## Per scout-grid point, for debug visualisation: its world position, the seconds_elapsed()
## time it was last observed (negative sentinel until first seen), and whether it has ever
## been in sight. The expiry window is SCOUT_EXPIRATION_TIMER.
func debug_points() -> Array:
	var out: Array = []
	for idx: Vector2i in _scout_grid:
		(
			out
			. append(
				{
					"position": _scout_grid_positions[idx],
					"last_seen": _scout_grid[idx],
					"ever_seen": _ever_seen.has(idx),
				}
			)
		)
	return out


## Per live scout, for debug visualisation: the unit, the waypoint it was last sent to (null
## before its first), how long it has gone without progress, and whether it is waiting for a
## waypoint. Freed and held (garrisoned) scouts are left out: neither stands anywhere.
func debug_scouts() -> Array:
	var now: float = _bot.seconds_elapsed()
	var out: Array = []
	for scout: Variant in _scouts:
		if not is_instance_valid(scout) or not (scout as Node).is_inside_tree():
			continue
		var record: Dictionary = _scout_progress.get((scout as Node).get_instance_id(), {})
		(
			out
			. append(
				{
					"unit": scout,
					"goal": record.get("goal"),
					"stalled_for": now - float(record.get("since", now)),
					"waiting": _dispatch_queue.has(scout),
				}
			)
		)
	return out


# ─── GRID CONSTRUCTION ───────────────────────────────────────────────────────


func _build_scout_grid() -> void:
	if _bot.map == null or _bot.map.height_map == null:
		return
	var hs: HeightMapShape3D = _bot.map.height_map
	_map_inverse = _bot.map.global_transform.affine_inverse()
	_map_width = float(hs.map_width - 1)
	_map_depth = float(hs.map_depth - 1)
	_map_half_w = _map_width * 0.5
	_map_half_d = _map_depth * 0.5

	var max_i: int = ceili(_map_width / float(SCOUT_GRID_SIZE))
	var max_j: int = ceili(_map_depth / float(SCOUT_GRID_SIZE))
	var init_ts: float = -(SCOUT_EXPIRATION_TIMER + 1.0)

	for i: int in range(max_i + 1):
		for j: int in range(max_j + 1):
			var idx := Vector2i(i, j)
			_scout_grid[idx] = init_ts
			var world_pos: Vector3 = _grid_world_pos(idx)
			world_pos.y = _bot.map.terrain_height_at(VU.in_xz(world_pos))
			_scout_grid_positions[idx] = world_pos


## World-space position of grid index (i, j). The map's global_transform handles
## any translation or scale so this is correct even when the map is not at origin.
func _grid_world_pos(a_idx: Vector2i) -> Vector3:
	var local := Vector3(
		-_map_half_w + min(float(a_idx.x) * SCOUT_GRID_SIZE, _map_width),
		0.0,
		-_map_half_d + min(float(a_idx.y) * SCOUT_GRID_SIZE, _map_depth)
	)
	return _bot.map.global_transform * local


# ─── LOS UPDATE ──────────────────────────────────────────────────────────────


## Mark the scout-grid points `a_unit` has in sight; returns the work units it cost. Gated
## on the unit's ACTUAL vision radius — the same shape the fog of war reveals with — and then
## on the FOG ITSELF: a point is scouted exactly when the bot's fog is clear there, which is
## the same signal the player's screen shows. This sweep used to cast a physics ray against
## terrain and structure blockers as well, but the fog has no line-of-sight test
## (Fog._vision_offsets is a flat footprint), so the bot was inventing an occlusion the game
## does not have and sending scouts back to ground it could already see — ontology.md
## §Vision is unoccluded. The ray's cost went with it.
##
## Only the grid points in a window around the unit are tested, not the whole grid: the window
## is the vision radius in grid steps plus one step of slack, because the unit stands anywhere
## between grid points. Testing the whole grid for every unit cost O(units × grid) per pass,
## which scaled with map area and was most of the bot's decision cost (bot-performance.md).
func _mark_seen_by(a_unit: Actor) -> int:
	var vision: float = _bot.vision_radius(a_unit)
	if vision <= 0.0:
		return 0
	var now: float = _bot.seconds_elapsed()
	var radius_sq: float = vision * vision
	var unit_xz: Vector2 = VU.in_xz(a_unit.global_position)
	var centre: Vector2i = _grid_index_at(unit_xz)
	var reach: int = ceili(vision / float(SCOUT_GRID_SIZE)) + 1
	var spent: int = 0
	for j: int in range(centre.y - reach, centre.y + reach + 1):
		for i: int in range(centre.x - reach, centre.x + reach + 1):
			var idx := Vector2i(i, j)
			if not _scout_grid_positions.has(idx):
				continue
			spent += SIGHT_POINT_WORK_UNITS
			var pt: Vector3 = _scout_grid_positions[idx]
			if unit_xz.distance_squared_to(VU.in_xz(pt)) > radius_sq:
				continue
			spent += SIGHT_FOG_READ_WORK_UNITS
			if _bot.has_vision_at(pt):
				_scout_grid[idx] = now
				_ever_seen[idx] = true
	return spent


# ─── SCOUT UNIT ASSIGNMENT ───────────────────────────────────────────────────


## Each think: give up the scouts that are no longer ours to keep, claim another if one is
## WORTH claiming, and (re-)issue a waypoint to every scout that needs one. Runs every think
## so a scout can claim an idle unit in the same tick it goes idle — before the military's
## idle-sweep can issue it an AttackMove instead.
##
## A CLAIM IS HELD, and that is the correction. It used to be dropped the moment any other
## manager re-tasked the unit, which made this module the weakest claimant in the bot: it
## runs FIRST precisely so it gets first refusal (BotBrain.think), and then surrendered
## whatever it had picked. What surrendered it was not a considered claim but
## BotMilitary's whole-army re-task, which fires on every posture or objective change and
## takes every unit with COMBAT UTILITY — including the Colonial Stock Truck, which has no
## weapon but can crush. Measured on a Colonial mirror: the truck was claimed on the first
## think, overwritten with an AttackMove by the military in that same think, and never held
## again for the rest of the match; it spent the game shuffling around the base centroid
## while a Servant at half its speed did the scouting
## (gdd/systems/ai/bot-architecture.md §Scouting).
##
## So the module now gives a scout up for exactly two reasons — it is wanted for a real
## errand (_yields_to_errand), or its absence has stopped paying for itself
## (_scouting_is_worth_it at its own rank) — and answers anything else by re-issuing the
## waypoint. The second reason is what keeps this from being a unit the army can never have:
## once the map is known the value collapses and the scouts are released of their own accord.
func _update_scouts(a_allowance: int = BotJob.UNLIMITED_WORK_UNITS) -> int:
	_work = 0
	# A bot with no allowance releases whatever it was scouting with, before asking anything
	# about them. Released rather than left standing, so the military's idle-sweep picks the
	# unit up next tick.
	if unit_budget <= 0:
		for entry: Variant in _scouts:
			claims.release(entry, CLAIM_OWNER)
		_scouts = []
		return _work
	var now: float = _bot.seconds_elapsed()
	# THE VALIDITY SWEEP GOES THROUGH A VARIANT, and it has to: Godot type-checks an object
	# against a typed local on ASSIGNMENT, and a freed instance fails that check before any
	# is_instance_valid() guard in the body can run — so `var held: Actor = _scouts[i]`
	# errors out and takes the whole think pass with it the first time a scout dies
	# (CLAUDE.md §A freed object cannot be passed to a typed parameter).
	var live: Array = []
	for entry: Variant in _scouts:
		# GARRISONED counts as gone too, and not only as a tidiness matter: a unit taken into a
		# garrison (run over by a Stock Truck, or ordered to occupy one) is a valid object that
		# has left the scene tree, so it has no global_position for the stall test to measure
		# progress against and warns every think for the rest of the match. Actor.
		# is_garrisoned is the right question rather than is_inside_tree(), which cannot tell a
		# held unit from a dead one (commandable.gd §garrisoned_in).
		#
		# TAKEN counts as gone too: a manager with a stronger claim (a build job, a fight) has it
		# now, and this module learns so here rather than by having run first.
		if (
			is_instance_valid(entry)
			and not (entry as Actor).is_garrisoned()
			and not _taken_by_another(entry)
		):
			live.append(entry)

	var kept: Array = []
	for i: int in live.size():
		# Rank i + 1: this is the (i+1)-th scout out, and the (i+1)-th scout is worth a fraction
		# 1/(i+1) of the whole map — the same divisor that authorised claiming it.
		if _still_scouting(live[i], i + 1):
			kept.append(live[i])
			claims.claim(live[i], CLAIM_OWNER, BotClaims.Priority.SCOUT)
		else:
			claims.release(live[i], CLAIM_OWNER)
	_work += _scouts.size() * CANDIDATE_WORK_UNITS
	_scouts = kept

	# One claim per think: taking the whole allowance at once would commit the bot to a
	# scouting posture on a single instant's reading of how blind it is.
	if _scouts.size() < unit_budget:
		var candidate: Variant = _pick_scout()
		if candidate != null:
			_scouts.append(candidate)
			claims.claim(candidate, CLAIM_OWNER, BotClaims.Priority.SCOUT)
			_dispatch_queue.append(candidate)

	# Send the next waypoint to any scout that has finished its last one, has been re-tasked
	# out from under us, or has stopped making ground toward it — which are the same situation
	# as far as this module is concerned: the waypoint is not going to be reached, and standing
	# there sees nothing.
	for scout: Actor in _scouts:
		if (
			(not scout.has_command() or _was_retasked(scout) or _is_stalled(scout, now))
			and not _dispatch_queue.has(scout)
		):
			_dispatch_queue.append(scout)
	_prune_progress()
	_drain_dispatch(a_allowance)
	return _work


## Give waypoints to the scouts in _dispatch_queue until `a_allowance` work units are spent,
## leaving the rest — and a part-run search — for the next call.
func _drain_dispatch(a_allowance: int) -> void:
	while not _dispatch_queue.is_empty() and _work < a_allowance:
		var head: Variant = _dispatch_queue[0]
		if (
			not is_instance_valid(head)
			or not _scouts.has(head)
			or not (head as Node).is_inside_tree()
		):
			_dispatch_queue.pop_front()
			_errand = {}
			continue
		var scout: Actor = head
		if _errand.is_empty() or _errand["scout"] != scout:
			_errand = _start_errand_search(scout, true)
		if not _continue_errand_search(_errand, a_allowance - _work):
			return  # out of budget part-way through; resume here next call
		# The frontier first; only when none is left, anywhere merely stale.
		if _errand["best_idx"] == null and _errand["unseen_only"]:
			_errand = _start_errand_search(scout, false)
			continue
		var best: Variant = _errand["best_idx"]
		_errand = {}
		_dispatch_queue.pop_front()
		if best != null:
			_send_to(scout, best, _bot.seconds_elapsed())


## True when another manager holds `a_unit` — it was taken from this module by a stronger claim.
func _taken_by_another(a_unit: Actor) -> bool:
	return claims.is_claimed(a_unit) and not claims.owns(a_unit, CLAIM_OWNER)


## WHETHER A SCOUT ALREADY OUT IS STILL OURS TO KEEP — the retention half of the claim, and
## the only place a held scout is given up.
##
## Three ways to lose one, and no fourth. It has been taken into a garrison or destroyed; it
## has been given a real errand (_yields_to_errand); or the map it is filling in has stopped
## being worth its absence at the rank it occupies. Everything else — in practice BotMilitary
## re-tasking the whole army, which claims a Stock Truck because a truck can crush — is
## answered by re-issuing the waypoint rather than by surrendering the unit.
##
## `a_scout` is untyped because a freed instance fails a typed assignment before any guard in
## the body can run (CLAUDE.md §A freed object cannot be passed to a typed parameter).
func _still_scouting(a_scout: Variant, a_rank: int) -> bool:
	if not is_instance_valid(a_scout):
		return false
	var scout: Actor = a_scout
	if scout.is_garrisoned():
		return false
	if _yields_to_errand(scout):
		return false
	return _scouting_is_worth_it(scout, a_rank)


## Issue `a_scout`'s next waypoint. The target is optimistically stamped as visited so
## _next_scout_point never re-selects the same cell — for this scout if its arrival leaves
## the point's fog pixel uncleared at the disc's edge, and for the OTHER scouts, which is
## what keeps two of them from walking to the same place.
func _send_to_next_point(a_scout: Actor, a_now: float) -> void:
	var next_idx: Variant = _next_scout_point(a_scout)
	if next_idx != null:
		_send_to(a_scout, next_idx, a_now)


## Stamp grid point `a_idx` as visited and send `a_scout` to it — see _send_to_next_point.
func _send_to(a_scout: Actor, a_idx: Vector2i, a_now: float) -> void:
	_scout_grid[a_idx] = a_now
	_act.move([a_scout], _scout_grid_positions[a_idx])
	# A fresh waypoint restarts the stall clock: the scout has not failed at this one yet.
	_scout_progress[a_scout.get_instance_id()] = {
		"at": a_scout.global_position, "since": a_now, "goal": _scout_grid_positions[a_idx]
	}


## True when `a_scout` has held its waypoint for SCOUT_STALL_SECONDS without covering
## SCOUT_STALL_DISTANCE — i.e. it is not going to get there. Records progress as a side
## effect, so calling it once per think is what keeps the measurement honest.
func _is_stalled(a_scout: Actor, a_now: float) -> bool:
	var key: int = a_scout.get_instance_id()
	var record: Variant = _scout_progress.get(key)
	if record == null or a_scout.global_position.distance_to(record["at"]) > SCOUT_STALL_DISTANCE:
		var goal: Variant = record["goal"] if record != null else null
		_scout_progress[key] = {"at": a_scout.global_position, "since": a_now, "goal": goal}
		return false
	return a_now - float(record["since"]) >= SCOUT_STALL_SECONDS


## Drop progress records for units that are no longer scouting, so the dictionary tracks the
## live scout set rather than growing for the length of a match.
func _prune_progress() -> void:
	var live: Dictionary = {}
	for scout: Actor in _scouts:
		live[scout.get_instance_id()] = true
	for key: int in _scout_progress.keys():
		if not live.has(key):
			_scout_progress.erase(key)


## IS ANOTHER SCOUT WORTH IT — the trade-off, priced in energy.
##
## Against: what the unit is worth × the share of that the bot expects to forfeit by having
## it away. For: what the map it would uncover is worth, which is the authored information
## price scaled by how blind the bot currently is, and DIVIDED BY the number of scouts
## already out. That divisor is the whole answer to "why not scout with everything": the
## second scout is worth half the first, the third a third, while each costs full price.
##
## The consequences fall out rather than being written: the bot scouts hard when it knows
## nothing, tails off as the map fills in, prefers to risk something cheap, and — because
## _pick_scout has already discounted units with live jobs — reaches for the unit
## nobody else wants first.
## `a_rank` is WHICH scout this one would be — 1 for the first out, 2 for the second — and
## defaults to "the next one after those already out". It is a parameter because the same
## question is now asked of a scout already in the field, to decide whether keeping it out
## still pays; asking that with the claim-time divisor would price every held scout as if it
## were an additional one and release them all.
func _scouting_is_worth_it(a_candidate: Actor, a_rank: int = 0) -> bool:
	var rank: int = a_rank if a_rank > 0 else _scouts.size() + 1
	var value: float = INFORMATION_VALUE_ENERGY * stale_fraction() / float(rank)
	return value > float(_bot.unit_cost(a_candidate.id)) * ABSENCE_RISK


## Fraction of the scout grid whose last sighting has expired — how blind the bot is now.
## 1.0 before anything has been seen, 0.0 when everything is currently fresh.
func stale_fraction() -> float:
	if _scout_grid.is_empty():
		return 0.0
	var threshold: float = _bot.seconds_elapsed() - SCOUT_EXPIRATION_TIMER
	var stale: int = 0
	for idx: Vector2i in _scout_grid:
		if _scout_grid[idx] < threshold:
			stale += 1
	return float(stale) / float(_scout_grid.size())


## True when a scout's command is no longer the plain move this module gave it — something
## else has re-tasked it, so its waypoint needs re-issuing. NOT the same question as whether
## the scout is still ours: see _yields_to_errand.
func _was_retasked(a_scout: Actor) -> bool:
	if not a_scout.has_command():
		return false  # idle after reaching a waypoint, still ours
	var c: MoveCommand = a_scout.current_command()
	return (
		c is Attack
		or c is AttackMove
		or c is Build
		or c is Assemble
		or c is Repair
		or c is Occupy
		or c is Capture
		or c is Land
		or c is Interact
	)


## WHEN A SCOUT STOPS BEING OURS: it has been given a job that must run to completion.
##
## Every re-task on _was_retasked's list EXCEPT AttackMove. The distinction is the whole of
## the claim-holding fix: an Attack, a Build, a Capture or a garrison order is a specific
## piece of work somebody decided this unit should do, and interrupting it wastes the walk
## that has already happened. An ATTACK-MOVE is not that — BotMilitary issues it to the whole
## army on every posture or objective change, including the MASS posture's "come and stand at
## home", so it is a standing rally rather than a decision about this unit. Yielding to it is
## what cost the bot its best scout on the first think of every match.
func _yields_to_errand(a_scout: Actor) -> bool:
	if not a_scout.has_command():
		return false
	var c: MoveCommand = a_scout.current_command()
	return (
		c is Attack
		or c is Build
		or c is Assemble
		or c is Repair
		or c is Occupy
		or c is Capture
		or c is Land
		or c is Interact
	)


## Among all owned units free to scout, the best-scoring one whose absence the bot can
## actually justify — see _scout_score and _scouting_is_worth_it. Null when none qualifies.
##
## THE TWO TESTS ARE APPLIED TOGETHER, and that is a fix rather than a tidy-up. This used to
## return the single best-scoring candidate and let the caller price it; if that one candidate
## failed the price test the think ended with nothing claimed, even when a cheaper unit
## standing next to it would have passed. The failure is systematic rather than occasional,
## because the two tests pull in opposite directions on the same fact: the scorer rewards
## capability, the price test punishes replacement cost, so the top-scoring candidate is the
## one most likely to be unaffordable. Measured on a Colonial mirror, that permanently pinned
## a MEDIUM bot (`scout_unit_budget` 2) at ONE scout: the Stock Truck won the score every
## think and was rejected at 400 energy × 0.5 against a second scout's 400 × stale ÷ 2
## (gdd/systems/ai/bot-architecture.md §Scouting).
func _pick_scout() -> Variant:
	var candidates: Array = _bot.get_units().filter(
		func(u: Actor) -> bool:
			if not u.can_move():
				return false
			# AOE-suicide drones are reserved for BotKamikaze (which alone commits them to a
			# blast run or holds them back) — never spend one wandering as a scout, mirroring
			# how BotMilitary / BotTargeting exclude them.
			if _bot.is_suicide_aoe_unit(u):
				return false
			return (
				not _scouts.has(u)
				and _unit_is_available(u)
				and claims.can_claim(u, CLAIM_OWNER, BotClaims.Priority.SCOUT)
			)
	)
	_work += _bot.get_units().size() * CANDIDATE_WORK_UNITS
	if candidates.is_empty():
		return null

	# Each term is normalised against the BEST candidate rather than against an absolute
	# scale, so the weights below stay meaningful whatever the game's speeds and prices are
	# calibrated to — which is the point: re-tune a unit's speed or vision and the bot's
	# choice of scout follows without a bot change.
	var scales: Dictionary = _score_scales(candidates)
	# Ranked by a draw at the bot's temperature rather than by a sort, so which unit goes
	# looking varies by match; with no generator or at 0 it is the sort it was.
	var scores: Array = candidates.map(
		func(u: Actor) -> float: return _scout_score(u, scales)
	)
	var ranked: Array = []
	for i: int in BotSampling.order(scores, decision_temperature, rng):
		ranked.append(candidates[i])
	var rank: int = _scouts.size() + 1
	for u: Actor in ranked:
		if _scouting_is_worth_it(u, rank):
			return u
	return null


## Denominators for the normalised score terms: the largest value each fact takes across
## `a_candidates`, floored at 1.0 so a term nobody scores on contributes 0 rather than
## dividing by zero.
func _score_scales(a_candidates: Array) -> Dictionary:
	var scales: Dictionary = {"speed": 1.0, "vision": 1.0, "cost": 1.0, "build_time": 1.0}
	for u: Actor in a_candidates:
		scales["speed"] = maxf(scales["speed"], u.movement.speed)
		scales["vision"] = maxf(scales["vision"], _bot.vision_radius(u))
		scales["cost"] = maxf(scales["cost"], float(_bot.unit_cost(u.id)))
		scales["build_time"] = maxf(scales["build_time"], float(_bot.unit_build_time_ticks(u.id)))
	return scales


## WHAT MAKES A GOOD SCOUT, as a comparison over facts rather than as a rule.
##
## It used to be "the fastest unit", which is one term of four and gave the wrong answer
## whenever the fastest thing owned was also the thing most needed elsewhere. The four:
##
##   • SPEED and VISION — how much map a unit converts into information per second.
##   • REPLACEMENT COST — energy and build time. A scout is alone and deep in enemy
##     territory by design, so the question is not only what it sees but what is lost when
##     it does not come back.
##   • RESPONSIBILITY — how many of its OTHER jobs are live right now (see
##     _applicable_responsibility_count). This is the term that makes the Colonial Stock
##     Truck the right opening scout without naming it: it is unarmed, it cannot build, and
##     its capture-and-deposit job has no target until enemy infantry is in sight, so early
##     on it is the only unit nobody else wants.
##
## The WEIGHTS are placeholders on the same footing as the difficulty ramp — the shape is
## settled, the numbers are what the self-play harness exists to search
## (gdd/systems/ai/bot-roadmap.md §The training harness). Do not balance against them.
func _scout_score(a_unit: Actor, a_scales: Dictionary) -> float:
	var speed: float = a_unit.movement.speed / a_scales["speed"]
	var vision: float = _bot.vision_radius(a_unit) / a_scales["vision"]
	var cost: float = float(_bot.unit_cost(a_unit.id)) / a_scales["cost"]
	var build_time: float = float(_bot.unit_build_time_ticks(a_unit.id)) / a_scales["build_time"]
	var responsibilities: float = float(_applicable_responsibility_count(a_unit))
	return (
		W_SPEED * speed
		+ W_VISION * vision
		- W_REPLACEMENT_ENERGY * cost
		- W_REPLACEMENT_TIME * build_time
		- W_RESPONSIBILITY * responsibilities
	)


## How many of this unit's OTHER jobs currently have something to do — one per manager that
## would otherwise claim it, counted only when that manager has live work:
##
##   • the army (BotMilitary) claims anything armed, and wanting an army is standing work;
##   • construction (BotEconomy) claims a builder, but only matters while it is the last one
##     — a second builder is spare;
##   • capture and liberation (BotOpportunist) claim an Interactor / Liberator, but only
##     while a target for that errand exists, or the unit is already carrying captives.
##
## Counted rather than valued, deliberately. Pricing "this unit's other job" against "seeing
## the enemy base" is the cross-domain currency the roadmap has not settled
## (gdd/systems/ai/bot-roadmap.md §Then: arbitration, not sequence); a count needs no such
## currency because every candidate here is being asked the same single question.
func _applicable_responsibility_count(a_unit: Actor) -> int:
	var count: int = 0
	# ARMED, deliberately, and not Bot.unit_has_combat_utility — even though BotMilitary now
	# marches crushers too. The question here is whether a unit is NEEDED ELSEWHERE, and
	# crushing is contact damage a unit does wherever it happens to be rather than a job that
	# keeps it somewhere. Counting it would also undo the property this scorer was built for:
	# the Colonial Stock Truck is the right opening scout precisely because nobody else has
	# live work for it, and a crush it can perform on the way does not change that.
	if a_unit.weapon_inventory != null and a_unit.weapon_inventory.has_weapons():
		count += 1
	if a_unit.has_node("Builds") and _builder_count() <= 1:
		count += 1
	if a_unit.interactor != null and not _bot.get_capturable_enemies().is_empty():
		count += 1
	if a_unit.liberator != null and not _bot.get_neutral_terrestrials().is_empty():
		count += 1
	if a_unit.garrison != null and not a_unit.garrison.occupants().is_empty():
		count += 1  # carrying something it is meant to deliver
	return count


## How many build-capable units the bot owns — what decides whether pulling this one away
## would leave the economy with no builder at all.
func _builder_count() -> int:
	return _bot.get_units().filter(func(u: Actor): return u.has_node("Builds")).size()


## True when a unit is unoccupied and safe to draft as a scout.
func _unit_is_available(a_u: Actor) -> bool:
	if not a_u.has_command():
		return true
	var c: MoveCommand = a_u.current_command()
	return not (
		c is Attack
		or c is AttackMove
		or c is Build
		or c is Assemble
		or c is Repair
		or c is Occupy
		or c is Capture
		or c is Land
		or c is Interact
	)


## WHERE THE SCOUT GOES NEXT: the errand with the best EXPECTED RETURN — how much it
## expects to see, weighted by how likely the enemy is to be there, per second of walking.
## Frontier (never-seen) errands are considered first and merely-stale ones only when there
## is no frontier left. Null when everything is fresh.
##
## THE FRONTIER COMES FIRST, and that ordering has not changed. A cell nobody has ever laid
## eyes on is not the same as a cell seen 61 seconds ago, and the second kind is always
## nearer, because the bot's own base and army refresh a disc around home continuously and
## everything just outside that disc re-expires every SCOUT_EXPIRATION_TIMER seconds. One
## pass over "expired" therefore re-walked the neighbourhood forever: `observed_fraction`
## climbed to ~0.27 by minute four of a 20-minute match and FROZE
## (gdd/systems/ai/bot-engagement-fixes.md).
##
## WHAT HAS CHANGED IS HOW ONE OF THOSE POINTS IS PICKED, and it is why the bot took most of
## a match to lay eyes on the enemy's half of the map. It used to be the NEAREST frontier
## point, which is the correct answer to "cover the most ground per second" and the wrong
## answer to "find somebody": nearest-first is a spiral, and a spiral fills in the bot's own
## corner before it ever starts on the far side. Measured on a Colonial mirror, the closest
## the seen set got to the opposing start point did not move at all over the first two
## simulated minutes (gdd/systems/ai/bot-architecture.md §Scouting).
##
## Three facts decide it now, and all three are things this bot can see:
##
##   • WHAT IT EXPECTS TO SEE — _expected_sightings: the unseen points inside the scout's own
##     vision at the destination, PLUS the ones it sweeps up on the way. Counting the journey
##     is what makes a long errand cost-competitive: walking twice as far costs twice as long
##     and reveals roughly twice as much, so the rate is nearly flat in distance and the
##     nearest point loses its automatic win.
##   • HOW LIKELY THE ENEMY IS TO BE THERE — _enemy_prior. This is the term that decides
##     whether a scout ever crosses the map, and it is the ONE thing here that is a belief
##     rather than a measurement, so it is deliberately the weakest belief that is true of
##     any map worth playing: the opponent is not standing next to my own base, because I can
##     see my own base. A point's prior therefore rises with its distance from HOME — from
##     the bot's own base centroid, not from anything it has been told about the opponent.
##     **This is not knowledge of where the enemy starts.** The scout walks toward open map,
##     not toward a start point, and it learns nothing until it arrives and looks; whether
##     the bot may instead be told where the start points ARE is a separate question and a
##     larger one (gdd/systems/ai/bot-architecture.md §Scouting).
##   • WHAT THE WALK COSTS — the scout's own Movement.speed, so a fast unit is allowed to
##     reach further for the same return.
##
## Both passes still require the point to be EXPIRED, which is what keeps an UNREACHABLE
## frontier cell from trapping the scout: _send_to_next_point optimistically stamps the point
## it dispatches to, so a cell walked at and not actually seen drops out of the candidate set
## for a full expiry window instead of being re-picked every think.
func _next_scout_point(a_scout: Actor) -> Variant:
	if not is_instance_valid(a_scout):
		return null
	var from_xz: Vector2 = VU.in_xz(a_scout.global_position)
	var speed: float = 1.0
	if a_scout.movement != null:
		speed = maxf(0.1, a_scout.movement.speed)
	var window: Array = _vision_window(_bot.vision_radius(a_scout))
	var frontier: Variant = _best_errand(from_xz, speed, window, true)
	return frontier if frontier != null else _best_errand(from_xz, speed, window, false)


## The expired grid point with the best expected return for a scout standing at `a_from_xz`,
## or null when there is none. `a_unseen_only` restricts the search to points that have never
## been in sight — the frontier — rather than to every point whose last sighting
## has aged out.
##
## Takes the scout's FACTS rather than the scout: where it is, how fast it walks and how much
## it sees are the whole of what the choice depends on, and passing them keeps the selector
## answerable against a synthetic grid without a live unit in the scene tree.
func _best_errand(
	a_from_xz: Vector2, a_speed: float, a_window: Array, a_unseen_only: bool
) -> Variant:
	var search: Dictionary = _errand_search(null, a_from_xz, a_speed, a_window, a_unseen_only)
	_continue_errand_search(search, BotJob.UNLIMITED_WORK_UNITS)
	return search["best_idx"]


## A fresh errand search for `a_scout`, from where it stands now — see _errand_search.
func _start_errand_search(a_scout: Actor, a_unseen_only: bool) -> Dictionary:
	var speed: float = maxf(0.1, a_scout.movement.speed) if a_scout.movement != null else 1.0
	return _errand_search(
		a_scout,
		VU.in_xz(a_scout.global_position),
		speed,
		_vision_window(_bot.vision_radius(a_scout)),
		a_unseen_only
	)


## The state of one errand search: the facts it scores against, fixed when it starts, and how
## far through the grid it has got. `a_scout` is only which scout it is for (null in a bare
## query).
func _errand_search(
	a_scout: Variant, a_from_xz: Vector2, a_speed: float, a_window: Array, a_unseen_only: bool
) -> Dictionary:
	return {
		"scout": a_scout,
		"from": a_from_xz,
		"speed": a_speed,
		"window": a_window,
		"unseen_only": a_unseen_only,
		"points": _scout_grid.keys(),
		"cursor": 0,
		"expiry": _bot.seconds_elapsed() - SCOUT_EXPIRATION_TIMER,
		"home": VU.in_xz(_home_position()),
		"best_idx": null,
		"best_return": 0.0,
	}


## Score grid points for `a_search` until it has seen them all (returns true) or has spent
## `a_allowance` more work units (returns false, to be continued).
func _continue_errand_search(a_search: Dictionary, a_allowance: int) -> bool:
	var points: Array = a_search["points"]
	var from_xz: Vector2 = a_search["from"]
	var unseen_only: bool = a_search["unseen_only"]
	var expiry: float = a_search["expiry"]
	var budget_end: int = _work + a_allowance
	var cursor: int = a_search["cursor"]
	while cursor < points.size():
		if _work >= budget_end:
			a_search["cursor"] = cursor
			return false
		var idx: Vector2i = points[cursor]
		cursor += 1
		_work += ERRAND_POINT_WORK_UNITS
		if _scout_grid[idx] >= expiry:
			continue
		if unseen_only and _ever_seen.has(idx):
			continue
		var pt_xz: Vector2 = VU.in_xz(_scout_grid_positions[idx])
		var distance: float = from_xz.distance_to(pt_xz)
		var sightings: float = _expected_sightings(
			idx, from_xz, distance, a_search["window"], unseen_only, expiry
		)
		if sightings <= 0.0:
			continue
		# A floor under the travel time: arriving somewhere is never instant, and without it a
		# point the scout is already standing on divides the return by nothing.
		var seconds: float = maxf(1.0, distance / float(a_search["speed"]))
		var expected: float = sightings * _enemy_prior(pt_xz, a_search["home"]) / seconds
		if expected > float(a_search["best_return"]):
			a_search["best_return"] = expected
			a_search["best_idx"] = idx
	a_search["cursor"] = cursor
	return true


## HOW MANY POINTS THE SCOUT EXPECTS TO ADD by taking this errand: what it sees standing at
## the destination, plus what it sweeps up walking there.
##
## The destination term is exact — the candidate points inside the scout's vision window at
## `a_idx`. The corridor term is an ESTIMATE, and deliberately a cheap one: the path is
## sampled at grid-interval spacing, the fraction of samples that are themselves still
## candidates stands for how dark the corridor is, and that fraction is multiplied by how
## many grid cells a vision-wide corridor of this length covers. The alternative — testing
## every grid point against every candidate segment — is a thousand-by-thousand sweep on
## every dispatch, and this runs inside the think pass.
func _expected_sightings(
	a_idx: Vector2i,
	a_from_xz: Vector2,
	a_distance: float,
	a_window: Array,
	a_unseen_only: bool,
	a_expiry_threshold: float
) -> float:
	var at_destination: float = float(
		_window_count(a_idx, a_window, a_unseen_only, a_expiry_threshold)
	)
	if a_distance < float(SCOUT_GRID_SIZE):
		return at_destination

	var to_xz: Vector2 = VU.in_xz(_scout_grid_positions[a_idx])
	var samples: int = clampi(int(a_distance / float(SCOUT_GRID_SIZE)), 1, MAX_PATH_SAMPLES)
	var dark: int = 0
	for i: int in range(1, samples + 1):
		var along: Vector2 = a_from_xz.lerp(to_xz, float(i) / float(samples + 1))
		var sample_idx: Vector2i = _grid_index_at(along)
		if _is_candidate(sample_idx, a_unseen_only, a_expiry_threshold):
			dark += 1
	# Cells a corridor one vision WIDE and `a_distance` long covers, discounted by how much of
	# the sampled path was still dark. The window's point count stands in for its width.
	var corridor: float = a_distance / float(SCOUT_GRID_SIZE) * sqrt(float(a_window.size()))
	return at_destination + corridor * float(dark) / float(samples)


## HOW LIKELY THE ENEMY IS TO BE AT `a_pt_xz`, as a weight rather than a probability: it only
## ever ranks one candidate against another. Rises linearly with distance from home, from
## HOME_PRIOR_FLOOR on the bot's own doorstep to 1.0 at the furthest ground it could be.
##
## The floor is what keeps the bot from ignoring its own approaches entirely — a raid still
## has to be noticed — and 0 would make every point near home literally worthless.
func _enemy_prior(a_pt_xz: Vector2, a_home_xz: Vector2) -> float:
	var span: float = maxf(1.0, Vector2(_map_width, _map_depth).length())
	var reach: float = minf(1.0, a_home_xz.distance_to(a_pt_xz) / span)
	return HOME_PRIOR_FLOOR + (1.0 - HOME_PRIOR_FLOOR) * reach


## Where "home" is for the purpose of the prior: the base centroid, or the army's centre of
## mass when the bot owns no structures. Mirrors BotMilitary._home_anchor rather than sharing
## it, because a scout that has nothing to anchor on still has to go somewhere — Vector3.ZERO
## (the map centre) is a usable answer here and would be a bad rally point there.
func _home_position() -> Vector3:
	var base: Vector3 = _bot.base_centroid()
	return base if base != Vector3.ZERO else _bot.army_centroid()


## Candidate points inside the vision window centred on `a_idx` — what standing there adds.
func _window_count(
	a_idx: Vector2i, a_window: Array, a_unseen_only: bool, a_expiry_threshold: float
) -> int:
	var count: int = 0
	for offset: Vector2i in a_window:
		if _is_candidate(a_idx + offset, a_unseen_only, a_expiry_threshold):
			count += 1
	return count


## True when `a_idx` is a point this errand would still be adding: on the grid, expired, and
## (for a frontier errand) never actually seen.
func _is_candidate(a_idx: Vector2i, a_unseen_only: bool, a_expiry_threshold: float) -> bool:
	if not _scout_grid.has(a_idx):
		return false
	if float(_scout_grid[a_idx]) >= a_expiry_threshold:
		return false
	return not (a_unseen_only and _ever_seen.has(a_idx))


## The grid index nearest a world-space XZ position — the inverse of _grid_world_pos, used to
## sample what a scout would pass over on the way somewhere.
func _grid_index_at(a_xz: Vector2) -> Vector2i:
	var local: Vector3 = _map_inverse * Vector3(a_xz.x, 0.0, a_xz.y)
	return Vector2i(
		roundi((local.x + _map_half_w) / float(SCOUT_GRID_SIZE)),
		roundi((local.z + _map_half_d) / float(SCOUT_GRID_SIZE))
	)


## The grid offsets a unit seeing `a_vision_radius` covers from wherever it stands, cached by
## radius in grid steps — a small integer, so the cache holds one entry per distinct kind of
## eye the bot owns. Taken from the unit's OWN vision radius, which is what keeps "how much a
## stop is worth" a property of the unit rather than a constant in this file.
func _vision_window(a_vision_radius: float) -> Array:
	var steps: int = maxi(1, floori(a_vision_radius / float(SCOUT_GRID_SIZE)))
	if not _window_cache.has(steps):
		var offsets: Array = []
		for dx: int in range(-steps, steps + 1):
			for dy: int in range(-steps, steps + 1):
				if dx * dx + dy * dy <= steps * steps:
					offsets.append(Vector2i(dx, dy))
		_window_cache[steps] = offsets
	return _window_cache[steps]
