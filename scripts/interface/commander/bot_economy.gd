class_name BotEconomy
extends RefCounted

## BotEconomy — grows income and production capacity.
##
## Each think pass, with a free builder available:
##   1. While the bot owns fewer income structures than it currently WANTS, claim a free
##      ExtractionSite — see effective_income_target(), the one rung that reads the game.
##   2. When income is outpacing spending AND the purchase leaves the reserve banked, build
##      a production structure (more unit throughput — see _has_resource_surplus), else
##   3. Grow income by building an extractor on a free ExtractionSite.
## One builder serializes the work, which naturally rate-limits construction.
##
## Step 3 is a FALL-THROUGH, not only the else of step 2: a surplus with nothing to spend it
## on goes to income. It used to be the else alone, which meant the bot only ever looked at
## income once it was poorer than the reserve — and by then it could not afford an extractor.
##
## STEP 1 IS THE RESPONSIVE ONE, and it is the only rung here that is not a fixed ordering.
## Everything else in this ladder is the order it is written in; step 1 asks how safe the bot
## is right now and wants more income when the answer is "safe". See effective_income_target.
##
## WHICH structures it builds is NOT hardcoded — it's derived from the bot's
## buildable set (registry ∩ builder capabilities ∩ tech) classified by component
## (Production / EnergyExtractor). A newly-added buildable structure (e.g. a Hangar) is
## picked up automatically; see Bot.buildable_production_structure_types / _income_.
##
## The surplus test is deliberately simple and isolated in _has_resource_surplus()
## so difficulty settings can later make it smarter (e.g. true income-vs-spend
## rate tracking, target building counts, scouting-gated expansion).

## Energy the bot keeps banked. It is BOTH the trigger for expanding throughput (sitting
## above it, and not falling, means production isn't draining our income) AND a FLOOR under
## discretionary spending: no production structure here and no unit training in
## BotProduction may take the balance below it. See can_afford_above_reserve for why the
## floor half is not optional, and which purchases are exempt from it.
##
## A PARAMETER (BotDifficulty.economy_reserve), because greed is a handicap: a bot that banks
## more before expanding plays safe and slow, one that commits early snowballs. The default
## is the value every tier used before difficulty was a knob.
var reserve: int = 600

## How many construction jobs may be in flight at once. One at a time is what rate-limits
## the bot's expansion and keeps two builds off the same cells; raising it (BotDifficulty.
## build_concurrency) expands faster and pulls more fighters off the line to do it. Values
## below 1 are treated as 1 — a bot that cannot build at all is not a difficulty.
var build_concurrency: int = 1

## Ceiling on how many production structures the bot will put up, or -1 for NO CAP, which is
## what it does today: while it is in surplus it keeps adding capacity. A cap is the bot
## saying how much throughput it PLANS to own, which is the one half of the opening ladder
## that is a number rather than an ordering (BotDifficulty.production_structure_cap).
var production_structure_cap: int = -1

## HOW MANY INCOME STRUCTURES THE BOT WANTS BEFORE IT ADDS THROUGHPUT, when nothing is
## pressing. Higher = GREEDIER: more of the opening spent on extractors and less on the
## buildings that make army.
##
## A PARAMETER (BotDifficulty.income_structure_target) rather than a reordering of the rungs
## above, because "extractor before barracks" is only the special case at 1 and the whole
## opening is what a tuning run wants to move. It is a TARGET, not a floor under income: the
## bot still reaches income through the fall-through once it is met.
##
## **The target is what the bot wants when it is SAFE.** effective_income_target() bends it
## with how safe the bot currently is, which is what makes this a signal-driven decision
## rather than a build order — see there.
var income_structure_target: int = 1

## HOW MANY STATIC DEFENCES THE BOT WANTS STANDING, going-up ones included. A PARAMETER
## (BotDifficulty.defence_structure_target). The rung it drives sits between income and
## throughput: a static is a short-term positional investment (static-defence.md), bought
## ahead of the threat once there is a producer to protect, and never instead of one.
var defence_structure_target: int = 2

## What counts as an enemy PRESSURING the base, in world units — the same field
## BotMilitary and BotSanction read (BotDifficulty.defend_threat_radius), pushed here as
## a third consumer because "is something of mine being attacked" has to mean one thing
## across the bot. Used only by safety().
var defend_threat_radius: float = 10.0

## How far from the base centroid a stronghold spot may sit, in cells. The candidate set is
## the DISC between them, not a ring scan: every cell in the annulus is scored and the best
## one wins, so these bound the search rather than order it.
const SEARCH_MIN_RING: int = 2
const SEARCH_MAX_RING: int = 14

## THE RULER OF THE PLACEMENT SCORE: cost per cell of distance from the base centroid.
##
## Fixed at 1.0 and deliberately NOT a parameter. The score is only ever compared against
## other candidates for the same building, so multiplying every weight by one factor changes
## no decision and one of the terms has to be the unit of the scale — the same argument that
## keeps THREAT out of BotDifficulty's retarget weights. Every other placement weight below
## is therefore read as "per cell of sprawl I will pay for this".
const COMPACTNESS_WEIGHT: float = 1.0

## Cells of open ground beyond which more open ground stops being worth anything. Without a
## cap the corridor term is just "go to the middle of the map", which is the opposite of what
## it is for: it exists to stop the bot pinching its own lanes, not to push it into the open.
const CORRIDOR_CAP_CELLS: int = 4

## Below this the bot has no direction to orient against and the frame is degenerate — see
## _forward_direction.
const DIRECTION_EPSILON: float = 1e-6

## HOW FAR TOWARD THE BELIEVED THREAT A PRODUCTION STRUCTURE WANTS TO SIT, per cell, against
## COMPACTNESS_WEIGHT = 1.0 for sprawl. Production is where the army comes from, so pushing
## it up the threat axis shortens every reinforcement walk; the cost is a building closer to
## whatever is coming.
##
## A PARAMETER (BotDifficulty.place_frontage_bias — see gdd/systems/ai/bot-parameter-space.md).
## Above 1.0 the directional reward outruns the sprawl cost and the bot builds at the far
## edge of SEARCH_MAX_RING; 0.0 makes production directionless and the base concentric.
var place_frontage_bias: float = 0.6

## HOW FAR AWAY FROM THE BELIEVED THREAT EVERYTHING ELSE WANTS TO SIT, on the same scale.
## Infrastructure, the dominion structure and anything else the bot is not fighting out of
## are things it wants BEHIND itself. Same bounds and the same saturation as above.
var place_shelter_bias: float = 0.6

## WHAT KEEPING ITS OWN LANES OPEN IS WORTH, per cell of clearance around the spot (capped at
## CORRIDOR_CAP_CELLS). This is the "don't block my own movement" term: the hard constraint already
## refuses a placement that SPLITS the map, and this is the softer preference that keeps the
## bot from squeezing a corridor down to one cell on the way there.
##
## A PARAMETER (BotDifficulty.place_corridor_weight). Higher = looser, airier bases; 0 lets
## the bot pack buildings against terrain and against each other.
var place_corridor_weight: float = 0.8

## HOW LONG ONE CONSTRUCTION JOB MAY HOLD A SLOT before the bot writes it off.
##
## `tick()` returns at the very top while `build_concurrency` jobs are in flight, so a Build
## that never completes does not merely waste a builder — IT FREEZES THE WHOLE ECONOMY. No
## capacity, no infrastructure, no income, for the rest of the match, while the bank fills
## with energy the bot cannot spend.
##
## MEASURED, on the runs that added the income target: an instrumented match had one side
## take the top-of-tick "already building" exit on 537 of 539 think passes after its second
## extraction-site claim, and its structure count sat at 3 for five simulated minutes. Across
## twelve slot-trajectories, five froze for 90-270 s. The pre-existing ladder hid this
## because it reached for a site only when it was too poor to do anything else — the same
## reason `economy_reserve` looked like it worked (bot-economy-diagnosis.md).
##
## THIS IS BotScout.SCOUT_STALL_SECONDS' PROBLEM ONE MODULE OVER — an order that can never
## arrive never goes idle, so nothing ever releases the unit. It is a TIMEOUT rather than the
## scout's distance-over-time test because a builder standing still at its site is what
## CONSTRUCTING LOOKS LIKE, and no progress test can separate that from a builder stuck
## against terrain. Sized well above a walk across the map plus the slowest build.
const CONSTRUCTION_JOB_TIMEOUT_SECONDS: float = 90.0

## How close a candidate spot must be to a written-off one to count as the same place, in
## world units. Roughly one building's footprint.
const ABANDONED_SPOT_RADIUS: float = 2.0

## How close a candidate spot may come to one an in-flight construction job is already aimed
## at. A footprint's worth of ground plus margin: two sites this close are racing for the same
## cells, which is what `build_concurrency = 1` used to prevent by never running a second job.
##
## Deliberately a RADIUS rather than a real footprint overlap test: the claimed job's
## dimensions would have to be carried alongside its spot, and being a cell too conservative
## only costs the bot a slightly further site.
const CLAIMED_SPOT_RADIUS: float = 3.0

## Per constructing unit (by instance id): seconds_elapsed() when that job was first seen.
## Keyed by id rather than by the node so a dead builder's entry can be dropped without
## touching a freed reference — the BotScout._scout_progress convention.
var _job_started: Dictionary = {}

## Build targets the bot has written off as unreachable. Without this the rung that chose a
## bad spot picks it again on the very next think, and the bot trades a permanent freeze for
## a 90-second loop — which is worse, because it also spends a builder on it forever.
##
## Deliberately never expires. A spot is written off because the builder could not complete a
## job there, and nothing the bot does later changes the terrain; a bot that forgets would
## re-learn the same lesson at 90 seconds a time.
var _abandoned_spots: Array = []

## The owner name this module claims builders under (BotClaims). A build job runs to
## completion, so the army's rally leaves the builder alone until it does.
const CLAIM_OWNER: StringName = &"economy"

## Which manager owns which unit; the brain replaces this with the bot's shared registry. A
## fresh one by default, so a bare manager in a test sees every unit unclaimed.
var claims: BotClaims = BotClaims.new()

## Work units per unit looked at, per placement candidate scored, and per candidate put through
## the full placement check (BotScheduler counts work in units of roughly a microsecond on the
## calibration machine).
const UNIT_WORK_UNITS: int = 35
const CANDIDATE_WORK_UNITS: int = 3
const PLACEMENT_CHECK_WORK_UNITS: int = 700
## Work units per footprint origin scored while ranking candidates: it reads the obstacle
## distance of every cell of the footprint.
const RANK_ORIGIN_WORK_UNITS: int = 12

## A dominion source past the first is built only while its best site adds at least this
## fraction of what one earns alone — what stops a site-dependent route (Opticons) spreading
## forever. TODO: placeholder; what dominion is worth against energy (bot-roadmap.md) is what
## should decide it.
const MIN_DOMINION_SITE_FRACTION: float = 0.5

## How far from the base a dominion source may be placed, and the spacing of the candidate
## lattice, in cells. Bot policy rather than a fact about any route: how far out it will risk
## an undefended building. TODO: placeholder, as is DOMINION_EXPOSURE_PER_CELL.
const DOMINION_SURVEY_RADIUS_CELLS: int = 40
const DOMINION_SURVEY_STRIDE_CELLS: int = 5

## What a cell of placement cost is worth against the fraction of a lone source's income a site
## adds: 0.02 means fifty cells of sprawl cost as much as one whole Opticon's claim.
const DOMINION_EXPOSURE_PER_CELL: float = 0.02

## Work units per candidate scored in the dominion survey, and for taking the survey's snapshot.
## Measured on skirmish with seven Opticons standing: 197 candidates in 15.9 ms, setup 5.1 ms.
## The setup is not split across thinks, so each structure change costs one ~5 ms pass.
const DOMINION_SURVEY_WORK_UNITS: int = 80
const DOMINION_SURVEY_SETUP_WORK_UNITS: int = 5000

## Indices into a _dominion_survey entry.
const SURVEY_SCORE: int = 0
const SURVEY_POINT: int = 1
const SURVEY_FRACTION: int = 2

## The dominion site survey in progress or last finished, and what it was taken against
## (see _dominion_survey). Empty before the first.
var _dominion_search: Dictionary = {}

## Work spent by the current tick, accumulated by the helpers it calls. Reset each tick.
var _work: int = 0
## Work units the current tick may spend; unlimited outside a scheduled run, so a direct call
## (a test, a bench) always finishes its search.
var _allowance: int = BotJob.UNLIMITED_WORK_UNITS

## What _find_build_spot returns when it ran out of allowance part-way through its candidates:
## the rung that asked stops, and the search resumes on the next tick.
const SEARCH_PENDING: StringName = &"search_pending"

## A build-spot search that ran out of allowance: the type it is for, its ranked candidates, how
## far through them it got, and what they were ranked against. A resumable sweep's cursor (see
## BotJob) — checking ranked candidates one by one cost over 100 ms on a crowded base. Empty
## when no search is part-way through.
var _spot_search: Dictionary = {}

var _bot: Bot
var _act: BotActuator
var _prev_energy: int = 0
## Whether the bot is winning or losing — one of the three inputs to safety(). Optional, so
## a bare economy in a test still ticks; a null momentum simply drops that term.
var _momentum: BotMomentum


func _init(a_bot: Bot, a_act: BotActuator, a_momentum: BotMomentum = null) -> void:
	_bot = a_bot
	_act = a_act
	_prev_energy = a_bot.energy
	_momentum = a_momentum


## Run the build ladder, spending about `a_allowance` work units; a build-spot search that runs
## out resumes on the next call (has_pending_search). Returns the work units spent.
func tick(a_allowance: int = BotJob.UNLIMITED_WORK_UNITS) -> int:
	_work = _bot.get_units().size() * UNIT_WORK_UNITS
	_allowance = a_allowance
	_release_finished_jobs()
	_decide()
	_allowance = BotJob.UNLIMITED_WORK_UNITS
	return _work


## True while a build-spot search is part-way through its candidates.
func has_pending_search() -> bool:
	return (
		not _spot_search.is_empty()
		or (
			_dominion_search.has("points")
			and _dominion_search["ranked"].size() < _dominion_search["points"].size()
		)
	)


## Give back every builder whose construction job is over, so the army can rally it again.
func _release_finished_jobs() -> void:
	for unit: Variant in claims.units_of(CLAIM_OWNER):
		if not is_instance_valid(unit) or not _is_constructing(unit):
			claims.release(unit, CLAIM_OWNER)


## Order `a_builder` to build, and claim it for the job when the order is issued.
func _issue_build(a_builder: Commandable, a_type: StringName, a_spot: Vector3) -> bool:
	var issued: bool = _act.build(a_builder, a_type, a_spot)
	if issued:
		claims.claim(a_builder, CLAIM_OWNER, BotClaims.Priority.ERRAND)
	return issued


## One pass of the build ladder.
func _decide() -> void:
	var surplus: bool = _has_resource_surplus()
	_prev_energy = _bot.energy

	# BEFORE the rate limit, not after: a job that will never finish must give its slot back,
	# or the test below returns for the rest of the match. See CONSTRUCTION_JOB_TIMEOUT_SECONDS.
	_release_stalled_construction()

	# Construction jobs are rate-limited: wait for a builder to finish rather than pulling
	# another fighter off the line or racing two builds onto the same cells. `build_concurrency`
	# is how many the bot will run at once, and -1 lifts the limit entirely (IMPOSSIBLE).
	if (
		not BotDifficulty.is_build_uncapped(build_concurrency)
		and _construction_job_count() >= BotDifficulty.build_slots(build_concurrency)
	):
		return

	var builder: Commandable = _pick_builder()
	if builder == null:
		return

	# Priority: stand up the faction's dominion structure (the Compound, the first Opticon) if
	# we don't own one yet. Which structures those are is the faction's DominionRoute's answer,
	# so a new faction's dominion building is picked up with no change here.
	var dtype: Variant = _dominion_structure_to_build()
	if dtype != null:
		var dspot: Variant = _dominion_build_spot(dtype, 0.0)
		if dspot is Vector3:
			_issue_build(builder, dtype, dspot)
		return

	# Before expanding further, make sure there's infrastructure headroom: if we're low on
	# spare capacity, stand up the faction's infrastructure provider (power plant / safehouse)
	# first. While one is needed we don't add more buildings — if it's not
	# affordable yet we bank for it rather than digging the strain deeper.
	# Strain does not fall until the provider is FINISHED, so this rung stays true for the
	# whole build — an in-flight job for the same type is what stops a second builder joining.
	if _bot.needs_infrastructure_provider():
		var vtype: Variant = _infrastructure_structure_to_build()
		if vtype != null and _types_under_way().has(vtype as StringName):
			return
		if vtype != null:
			if _bot.can_afford(vtype):
				var vspot: Variant = _find_build_spot(vtype)
				if vspot is Vector3:
					_issue_build(builder, vtype, vspot)
			return

	# INCOME BEFORE THROUGHPUT, while the bot wants more income than it owns AND is safe
	# enough to go and get it. This is the rung the opening turned on: the bot used to spend
	# its whole starting grant on production buildings and finish its first extractor at a
	# mean of 125 s (gdd/systems/ai/bot-economy-diagnosis.md §What this does NOT settle).
	#
	# A FALL-THROUGH like the income rung below, deliberately: an unaffordable extractor or a
	# map with every site claimed drops to throughput rather than banking. Nothing is lost by
	# that — the capacity rung is gated on can_afford_above_reserve, which is strictly
	# stricter than affording an extractor, so a bot too poor for income buys nothing anyway.
	if _owned_income_structure_count() < effective_income_target():
		var etype: Variant = _income_structure_to_build()
		if etype != null:
			var espot: Variant = _income_build_spot()
			# Only a build that was actually ISSUED ends the think. A rung that could not act must
			# not block the ones below it — the same lesson the surplus branch's fall-through
			# records, and the reason this one is a fall-through too.
			if espot != null and _issue_build(builder, etype, espot):
				return

	# STATIC DEFENCE AHEAD OF THE THREAT, once there is a producer to stand in front of. The
	# ladder had no rung for a turret at all until 2026-10-04 — the defence types existed only
	# as a placement bearing — so a bot never built one however cheaply it traded. Below the
	# target, the defence whose gun best answers the enemy UNITS the bot has seen goes up on
	# the frontage bearing; like the rungs above it, a rung that could not act falls through.
	if _owned_defence_structure_count() < defence_structure_target and _owns_a_producer():
		var ftype: Variant = _defence_structure_to_build()
		if ftype != null:
			var fspot: Variant = _find_build_spot(ftype)
			if fspot is StringName:
				return  # still searching; the rest of the ladder waits for the answer
			if fspot is Vector3 and _issue_build(builder, ftype, fspot):
				return

	# A surplus first extends a dominion route that pays per SITE (more Opticons), while a site
	# is left that still pays enough — see _extend_dominion. Then production capacity.
	if surplus and _extend_dominion(builder):
		return

	# When income is outpacing spending, sink the surplus into more production
	# capacity. Built near the base, so the build completes reliably.
	if surplus:
		var ptype: Variant = _production_structure_to_build()
		if ptype != null:
			var spot: Variant = _find_build_spot(ptype)
			if spot is Vector3:
				_issue_build(builder, ptype, spot)
				return
			if spot is StringName:
				return  # still searching; the rest of the ladder waits for the answer
		# NOTHING TO ADD TO THROUGHPUT — capped out, nothing affordable above the reserve, or
		# nowhere to put it — so FALL THROUGH to income rather than idling. This `return` used
		# to be unconditional, and it is what made the extractor rung unreachable: the surplus
		# branch is entered whenever the balance is at or above the reserve, so a bot that could
		# not add capacity spent that whole regime doing nothing at all, and only looked at
		# income once it was already too poor to buy an extractor. Measured over the 85-match
		# corpus, 145 of 170 slot-trajectories finished with ZERO extractors and therefore zero
		# income — see gdd/systems/ai/bot-economy-diagnosis.md.

	# Grow income by claiming a free site with an extractor. Reached either because we are not
	# in surplus, or because the surplus had nowhere better to go.
	var mtype: Variant = _income_structure_to_build()
	if mtype != null:
		var spot: Variant = _income_build_spot()
		if spot != null:
			_issue_build(builder, mtype, spot)


## Which production structure to build now: an affordable buildable production type,
## PREFERRING one we don't own yet — so every production building gets built at least once
## to unlock its units — and within that, THE ONE WHOSE UNITS THE DEMAND WANTS MOST
## (Bot.best_producible_value against the enemy demand map), cost as the tiebreak. It used
## to be the cheapest, which after one of each meant a second barracks every time and never a
## second war factory however badly the army wanted vehicles. null when none is affordable.
func _production_structure_to_build() -> Variant:
	var buildable: Array = _bot.buildable_production_structure_types()
	if (
		production_structure_cap >= 0
		and _owned_production_structure_count(buildable) >= production_structure_cap
	):
		return null  # the bot has as much throughput as it plans to own
	var candidates: Array = buildable.filter(func(t): return can_afford_above_reserve(t))
	if candidates.is_empty():
		return null
	var unowned: Array = candidates.filter(
		func(t): return _bot.get_structures_of_type(t).is_empty()
	)
	var pool: Array = unowned if not unowned.is_empty() else candidates
	var demand: Dictionary = _bot.enemy_demand_map()
	var value: Dictionary = {}
	for t in pool:
		value[t] = _bot.best_producible_value(t, demand)
	pool.sort_custom(
		func(a, b):
			if value[a] != value[b]:
				return value[a] > value[b]
			return _energy_cost(a) < _energy_cost(b)
	)
	return pool[0]


## Which static defence to build now: the affordable buildable defence type whose weapons
## best counter the enemy UNITS the bot believes in (Bot.unit_composition_value over the
## demand map's unit entries — a turret answers an army, not a base), cost as the tiebreak
## and the whole choice when nothing has been seen yet. null when none is affordable.
func _defence_structure_to_build() -> Variant:
	var candidates: Array = _bot.buildable_defence_structure_types().filter(
		func(t): return can_afford_above_reserve(t)
	)
	if candidates.is_empty():
		return null
	var demand: Dictionary = _bot.enemy_demand_map()
	var unit_demand: Dictionary = {}
	for etype: Variant in demand:
		if not (demand[etype]["rep"] as Node).is_in_group("structure"):
			unit_demand[etype] = demand[etype]
	var value: Dictionary = {}
	for t in candidates:
		value[t] = _bot.unit_composition_value(t, unit_demand)
	candidates.sort_custom(
		func(a, b):
			if value[a] != value[b]:
				return value[a] > value[b]
			return _energy_cost(a) < _energy_cost(b)
	)
	return candidates[0]


## Standing static defences plus the ones going up — committed, like production capacity.
func _owned_defence_structure_count() -> int:
	var count: int = 0
	var under_way: Array[StringName] = _types_under_way()
	for t in _bot.buildable_defence_structure_types():
		count += _bot.get_structures_of_type(t).size() + under_way.count(t)
	return count


## Whether a production structure stands or is going up: the thing a static defence is for.
func _owns_a_producer() -> bool:
	return _owned_production_structure_count(_bot.buildable_production_structure_types()) > 0


## How many production structures the bot already owns, counting the types it can build and
## including ones still going up — an in-progress building is capacity it has already
## committed to, so a cap that ignored it would authorise one build too many every time.
func _owned_production_structure_count(a_buildable: Array) -> int:
	var count: int = 0
	for t in a_buildable:
		count += _bot.get_structures_of_type(t).size()
	return count


## HOW MANY INCOME STRUCTURES THE BOT WANTS RIGHT NOW: the searchable target
## (income_structure_target), scaled by how safe it currently is.
##
## THIS IS THE ANSWER TO "a build order should manifest from model signals". The target says
## what the bot wants when nothing is pressing; safety() says whether now is the moment. A
## player invests in resource acquisition when it is safe to do so, and puts the same energy
## into the units and buildings that fight when it is not — so:
##
##   GREEDY WHEN SAFE — safety near 1 keeps the whole target, and the extractor is bought
##     before the barracks.
##   CAPACITY WHEN THREATENED — safety near 0 collapses the target to 0, this rung does not
##     fire at all, and the ladder falls straight to production capacity, which is the only
##     lever the economy has for "commit to defence or offence".
##
## Safety only ever bends the target DOWN. A bot cannot become greedier than its parameter
## says; it can only be talked out of greed by the game.
##
## The rounding is honest about its own resolution: at a target of 1 this is a switch that
## flips at safety 0.5 (roundf rounds a half away from zero, so exact parity still buys the
## extractor). Real dynamic range starts at a target of 2, which is what a search is for.
func effective_income_target() -> int:
	return int(roundf(float(maxi(0, income_structure_target)) * safety()))


## HOW SAFE THE BOT IS, from 0.0 (something is being attacked, or it is badly outgunned and
## bleeding) to 1.0 (nothing pressing).
##
## Built from signals the bot ALREADY HAS, deliberately — no new perception layer, and in
## particular not the income sense bot-roadmap.md §Reading the game has queued, which is a
## larger piece of work and is not what this rung needs:
##
##   (a) IS ANYTHING OF MINE UNDER ATTACK (Bot.is_base_under_threat). Not a matter of
##       degree — an enemy inside the base is the definition of "now is not the moment".
##   (b) HOW OUTGUNNED DO I BELIEVE I AM — believed enemy army value against our own. This
##       is relative_threat_level's question asked FOG-LIMITED: that sense reads the live
##       scene and would hand the economy perfect knowledge of an army the bot has never
##       seen, which is exactly the omniscience the ATTACK objective was fog-limited to
##       remove (bot-architecture.md §The attack objective is a belief).
##   (c) AM I BLEEDING RIGHT NOW (BotMomentum.loss_rate, normalised by its own losing
##       threshold). Losses in progress are what separate "they are bigger than me" from
##       "they are killing me", and only the second is urgent.
##
## HAVING SEEN NOTHING READS AS SAFE, and that is the intended reading rather than an
## oversight: at match start the bot believes in no enemy and is not being attacked, so it
## expands — and being wrong about that is what makes scouting pay, the same argument the
## fog-limited attack objective rests on. Note the deliberate asymmetry with
## BotMilitary.assumed_enemy_parity, which assumes an unseen enemy exists: the humility
## prior is there to stop the bot ATTACKING on a phantom lead, and applying it here would
## instead stop it ever expanding on a map it has not scouted.
func safety() -> float:
	if _bot.is_base_under_threat(defend_threat_radius):
		return 0.0
	var out: float = 1.0
	var own: float = _bot.army_resource_value()
	var believed: float = _bot.believed_enemy_army_value()
	var total: float = own + believed
	if total > 0.0:
		out *= 1.0 - believed / total
	if _momentum != null:
		out *= 1.0 - clampf(_momentum.loss_rate() / BotMomentum.LOSING_LOSS_RATE, 0.0, 1.0)
	return clampf(out, 0.0, 1.0)


## How many income structures the bot owns, counting the buildable income types and
## INCLUDING ones still going up — an extractor under construction is income already
## committed to, so a target that ignored it would authorise one build per think until the
## first one finished. Mirrors _owned_production_structure_count, and is deliberately not
## Bot.extractor_count(), which counts only FINISHED extractors (it is an income index).
func _owned_income_structure_count() -> int:
	var count: int = 0
	for t in _bot.buildable_income_structure_types():
		count += _bot.get_structures_of_type(t).size()
	return count


## Cheapest affordable buildable dominion structure we don't own yet (currently the
## Compound), or null. We only stand up one — extra capacity is handled by the
## capture loop filling it, not by building more.
func _dominion_structure_to_build() -> Variant:
	# `get_structures_of_type` cannot see a building that has been ORDERED but not yet placed,
	# so an in-flight job counts as owning one. Without that, every extra concurrent job walks
	# this rung again and sends another builder to the same Compound.
	var under_way: Array[StringName] = _types_under_way()
	var candidates: Array = _bot.buildable_dominion_structure_types().filter(
		func(t):
			return (
				_bot.can_afford(t)
				and _bot.get_structures_of_type(t).is_empty()
				and not under_way.has(t)
			)
	)
	if candidates.is_empty():
		return null
	candidates.sort_custom(func(a, b): return _energy_cost(a) < _energy_cost(b))
	return candidates[0]


## Build ANOTHER source of a site-dependent dominion route, where its best site still adds at
## least MIN_DOMINION_SITE_FRACTION of what one earns alone. True when a build was issued.
##
## Only for a route whose sources pay by where they stand: one Compound earns what two would, so
## a site-independent route never reaches this. The first source is the top rung's, not this.
## Also true while the site survey is still running, which holds the rest of the ladder for the
## answer just as a pending build-spot search does.
func _extend_dominion(a_builder: Commandable) -> bool:
	var under_way: Array[StringName] = _types_under_way()
	for t: StringName in _bot.buildable_dominion_structure_types():
		if (
			under_way.has(t)
			or _bot.get_structures_of_type(t).is_empty()
			or not can_afford_above_reserve(t)
		):
			continue
		var spot: Variant = _dominion_site(t, MIN_DOMINION_SITE_FRACTION)
		if spot is StringName:
			return true  # still surveying; the rest of the ladder waits for the answer
		if spot is Vector3 and _issue_build(a_builder, t, spot):
			return true
	return false


## Where a dominion source of `a_type` goes: the best-paying site for a route that pays by site
## (as long as it adds at least `a_min_fraction` of a lone source), else the ordinary placement.
func _dominion_build_spot(a_type: StringName, a_min_fraction: float) -> Variant:
	var route: DominionRoute = _bot.dominion_route()
	var preview := _bot.get_build_preview_instance(Tool.for_type(a_type)) as Entity
	if (
		route == null
		or preview == null
		or route.full_site_gain(preview) == DominionRoute.NOT_SITE_DEPENDENT
	):
		return _find_build_spot(a_type)
	return _dominion_site(a_type, a_min_fraction)


## The best valid site for a site-dependent dominion source; null when no candidate adds at
## least `a_min_fraction` of a lone source's income (and always more than nothing), and
## SEARCH_PENDING while the survey is still running.
func _dominion_site(a_type: StringName, a_min_fraction: float) -> Variant:
	var ranked: Variant = _dominion_survey(a_type)
	if not ranked is Array:
		return ranked
	var dims: Vector2i = _dims_for_type(a_type)
	for entry: Array in ranked:
		if entry[SURVEY_FRACTION] <= 0.0 or entry[SURVEY_FRACTION] < a_min_fraction:
			continue
		var point: Vector2 = entry[SURVEY_POINT]
		var world: Vector3 = _bot.map.footprint_centroid(
			_bot.map.footprint_origin(point, dims), dims
		)
		_work += PLACEMENT_CHECK_WORK_UNITS
		if _placement_ok(world, dims, _home_region()):
			return world
	return null


## Every candidate site for `a_type`, best first, as [score, point, fraction of a lone source's
## income it would add] — or SEARCH_PENDING while it is still being scored. Candidates are a
## lattice around the base out to DOMINION_SURVEY_RADIUS_CELLS; the score is that fraction less
## DOMINION_EXPOSURE_PER_CELL for each cell of placement cost — distance from the base, and
## place_shelter_bias toward the believed threat, the cost every building behind the line pays.
##
## RESUMABLE, and memoized until the bot's structures change: scoring every candidate is several
## milliseconds of claim-walking, so it is spread over thinks within the allowance (as
## _find_build_spot is), and nothing it reads moves until a structure is placed, finished or
## lost. The threat direction can move in between; the next structure change refreshes it.
func _dominion_survey(a_type: StringName) -> Variant:
	var owned: Array = _bot._owned_structures()
	var key: Array = [
		a_type, owned.size(), owned.filter(func(o: Commandable) -> bool: return o.is_built).size()
	]
	if _dominion_search.get("key", []) != key:
		_dominion_search = _new_dominion_search(a_type, key)
	var search: Dictionary = _dominion_search
	if not search.has("points"):
		return []  # the route cannot price a site
	var points: Array[Vector2] = search["points"]
	var ranked: Array = search["ranked"]
	var survey: DominionSiteSurvey = search["survey"]
	var start: int = ranked.size()
	while ranked.size() < points.size():
		# At least one candidate per call, so a spent allowance still moves the survey on.
		if _work >= _allowance and ranked.size() > start:
			return SEARCH_PENDING
		var point: Vector2 = points[ranked.size()]
		var offset: Vector2 = point - search["anchor"]
		var cost_cells: float = (
			(offset.length() + place_shelter_bias * offset.dot(search["forward"])) / Map.CELL_SIZE
		)
		var fraction: float = survey.gain_at(point) / search["full"]
		ranked.append([fraction - DOMINION_EXPOSURE_PER_CELL * cost_cells, point, fraction])
		_work += DOMINION_SURVEY_WORK_UNITS
	if not search.get("sorted", false):
		ranked.sort_custom(
			func(a: Array, b: Array) -> bool: return a[SURVEY_SCORE] > b[SURVEY_SCORE]
		)
		search["sorted"] = true
	return ranked


## A fresh survey of `a_type`'s candidate sites, unscored; empty when the route cannot price one.
func _new_dominion_search(a_type: StringName, a_key: Array) -> Dictionary:
	var route: DominionRoute = _bot.dominion_route()
	var preview := _bot.get_build_preview_instance(Tool.for_type(a_type)) as Entity
	var survey: DominionSiteSurvey = (
		route.site_survey(preview) if route != null and preview != null else null
	)
	if survey == null:
		return {"key": a_key}
	_work += DOMINION_SURVEY_SETUP_WORK_UNITS
	var anchor: Vector2 = VU.in_xz(_bot.base_centroid())
	var points: Array[Vector2] = []
	var reach: int = DOMINION_SURVEY_RADIUS_CELLS / DOMINION_SURVEY_STRIDE_CELLS
	for j: int in range(-reach, reach + 1):
		for i: int in range(-reach, reach + 1):
			var offset := Vector2(i, j) * DOMINION_SURVEY_STRIDE_CELLS * Map.CELL_SIZE
			if offset.length() <= DOMINION_SURVEY_RADIUS_CELLS * Map.CELL_SIZE:
				points.append(anchor + offset)
	return {
		"key": a_key,
		"survey": survey,
		"points": points,
		"ranked": [],
		"anchor": anchor,
		"forward": _forward_direction(anchor),
		"full": route.full_site_gain(preview)
	}


## Cheapest buildable infrastructure provider (tech-available), regardless of affordability so
## the caller can bank for it. null when the faction has none in its buildable set.
func _infrastructure_structure_to_build() -> Variant:
	var candidates: Array = _bot.buildable_infrastructure_structure_types()
	if candidates.is_empty():
		return null
	candidates.sort_custom(func(a, b): return _energy_cost(a) < _energy_cost(b))
	return candidates[0]


## Cheapest affordable buildable income (extractor) structure, or null.
func _income_structure_to_build() -> Variant:
	var candidates: Array = _bot.buildable_income_structure_types().filter(
		func(t): return _bot.can_afford(t)
	)
	if candidates.is_empty():
		return null
	candidates.sort_custom(func(a, b): return _energy_cost(a) < _energy_cost(b))
	return candidates[0]


func _energy_cost(a_type) -> int:
	var spec: TechnologySpec = _bot.technology_mapping.get(a_type)
	return spec.energy_cost if spec != null else 0


## True when [type] is affordable AND paying for it still leaves `reserve` banked.
##
## THE RESERVE IS A FLOOR, NOT ONLY A TRIGGER, and this is the function that makes it one.
## `_has_resource_surplus` is a trigger — "am I rich enough to consider expanding" — and a
## trigger on its own cannot keep a balance: the bot cleared 600, bought a 900-energy
## building, and was under the reserve again before the next think. Nothing ever refused a
## purchase for breaching it, which is why the roadmap's stated purpose for the knob
## ("stop the bot spending down to zero so that it can always afford something") did not
## hold and 70% of sampled ticks had a balance of exactly zero.
##
## WHAT THE FLOOR APPLIES TO is discretionary GROWTH IN THROUGHPUT — extra production
## capacity here, and unit training in BotProduction. The income, infrastructure and
## dominion rungs are deliberately EXEMPT: those are the purchases the bank exists to keep
## affordable, so a floor that blocked them would bank for nothing.
func can_afford_above_reserve(a_type) -> bool:
	return _bot.can_afford(a_type) and _bot.energy - _energy_cost(a_type) >= reserve


## Are we earning faster than we spend? Simple proxy (overridable seam for
## difficulty tuning): energy is parked above a healthy reserve AND isn't falling,
## i.e. production training each tick still can't drain what the extractors bring in.
func _has_resource_surplus() -> bool:
	return _bot.energy >= reserve and _bot.energy >= _prev_energy


## How many owned units are in the middle of constructing (placing or repairing-to-complete
## a structure) — the number of build jobs currently in flight, which `build_concurrency`
## caps. Also what keeps the military from yanking an active builder back into the fight.
func _construction_job_count() -> int:
	var count: int = 0
	for u: Commandable in _bot.get_units():
		if _is_constructing(u):
			count += 1
	return count


## Abandon any construction job that has held its slot past CONSTRUCTION_JOB_TIMEOUT_SECONDS,
## and remember where it was aimed so the next think does not order the same one again.
##
## Clearing the command is also what refunds it: BotActuator.build registers the purchase on
## the commander's production queue with the command as its holder, so dropping the order
## returns the reservation rather than stranding it.
func _release_stalled_construction() -> void:
	var now: float = _bot.seconds_elapsed()
	var live: Dictionary = {}
	for u: Commandable in _bot.get_units():
		if not _is_constructing(u):
			continue
		var key: int = u.get_instance_id()
		live[key] = true
		if not _job_started.has(key):
			_job_started[key] = now
			continue
		if now - float(_job_started[key]) < CONSTRUCTION_JOB_TIMEOUT_SECONDS:
			continue
		var target: Variant = _construction_target(u)
		if target != null:
			_abandoned_spots.append(target)
		u.update_commands(null)
		_job_started.erase(key)
	for key: int in _job_started.keys():
		if not live.has(key):
			_job_started.erase(key)


## Where `unit`'s current construction order was aimed, or null when it has none.
func _construction_target(a_unit: Commandable) -> Variant:
	if not a_unit.has_command():
		return null
	var cmd: MoveCommand = a_unit.current_command()
	return cmd.message.position if cmd.message != null else null


## True when `world` is somewhere the bot has already failed to build. Consulted by every
## rung's spot choice, not only the one that failed: the reason a spot cannot be finished is
## a property of the place, not of what was being put there.
func _is_abandoned_spot(a_world: Vector3) -> bool:
	for spot: Vector3 in _abandoned_spots:
		if spot.distance_to(a_world) <= ABANDONED_SPOT_RADIUS:
			return true
	return false


## Where every in-flight construction job is aimed. A job that has not PLACED its structure
## yet is invisible to every "do I own one of these" check in the ladder — the structure does
## not exist to be counted — so without this a second job re-runs the ladder from the top,
## reaches the same rung, picks the same spot, and lands a second builder on the first one's
## site. That was harmless while only one job ever ran.
func _claimed_spots() -> Array[Vector3]:
	var spots: Array[Vector3] = []
	for unit: Commandable in _bot.get_units():
		if not _is_constructing(unit):
			continue
		var target: Variant = _construction_target(unit)
		if target is Vector3:
			spots.append(target)
	return spots


## True when `a_world` is close enough to an in-flight job's site to be the same build.
func _is_claimed_spot(a_world: Vector3) -> bool:
	for spot: Vector3 in _claimed_spots():
		if spot.distance_to(a_world) <= CLAIMED_SPOT_RADIUS:
			return true
	return false


## Every structure type an in-flight job is raising — a Build's tool, or the structure an
## Assemble is finishing. What makes a "we need exactly one of these" rung read an ordered
## building as already handled instead of ordering it twice.
func _types_under_way() -> Array[StringName]:
	var types: Array[StringName] = []
	for unit: Commandable in _bot.get_units():
		if not _is_constructing(unit):
			continue
		var command: MoveCommand = unit.current_command()
		if command.message == null:
			continue
		var target: Variant = command.message.target
		if target != null and is_instance_valid(target):
			types.append((target as Entity).id)
		elif command.message.tool != null:
			types.append(command.message.tool.type)
	return types


static func _is_constructing(u: Commandable) -> bool:
	if not u.has_command():
		return false
	var c: MoveCommand = u.current_command()
	return c is Build or c is Assemble


## Choose a unit to construct with. Build-capable units (Irregulars) are also
## fighters in this faction, which is intended — so we only ever pull ONE, and
## prefer an idle one to minimise disrupting the army; if none is idle we pull a
## fighter (it rejoins combat once the structure is finished). Returns null when
## the bot owns no builder yet.
func _pick_builder() -> Commandable:
	var busy_builder: Commandable = null
	for u: Commandable in _bot.get_units():
		if not u.has_node("Builds"):
			continue
		# Don't yank a unit mid-opportunity (e.g. a truck capturing/depositing) onto a
		# build job — that loop is committed work, like construction itself.
		if BotOpportunist.is_committed(u):
			continue
		# Nor one another manager holds as strongly (an errand runner, an exclusive owner).
		if not claims.can_claim(u, CLAIM_OWNER, BotClaims.Priority.ERRAND):
			continue
		# Nor one already on a build job. Reachable now that build_concurrency can exceed 1 (tick()
		# returns before here if anyone is building at all); it is what makes a higher
		# concurrency start a SECOND job rather than re-order the first builder's.
		if _is_constructing(u):
			continue
		if not u.has_command():
			return u  # idle builder — ideal
		busy_builder = u
	return busy_builder


## Where the next income structure goes: the nearest unworked EXTRACTION SITE or LITHIUM
## POND the bot has EXPLORED, whichever is closer to the base; null when it knows of none. A
## POSITION rather than the site itself, so the income rung has the same shape as the other
## two (a type and a spot).
##
## Fog-limited like the attack objective: a deposit the bot has never had in vision is one it
## does not know exists, so scouting is what feeds expansion (bot-architecture.md §Income is
## found by scouting).
##
## The bot only knew about sites until 2026-09-12, so every pond on a map was invisible to it
## — half the energy economy (gdd/setting/resources.md §Lithium ponds) that a human opponent
## could take uncontested.
##
## Distance is the whole comparison, deliberately matching what the site search already did.
## A pond pays `WaterBody.POND_RATE_MULTIPLIER` times faster and is FINITE, so "which is
## worth more" is a real question — and a value-over-time one, like every other open pricing
## question in this module.
##
## TODO — price a pond against a site rather than measuring both with a ruler. It needs the
## same currency the ability and Servant-garrison questions need; see bot-roadmap.md §What has
## to be modelled.
func _income_build_spot() -> Variant:
	var site: Entity = _nearest_unclaimed_site()
	var site_spot: Variant = site.global_position if site != null else null
	var pond_spot: Variant = _nearest_workable_pond_spot()
	if site_spot == null:
		return pond_spot
	if pond_spot == null:
		return site_spot
	var base: Vector3 = _bot.base_centroid()
	return (
		pond_spot
		if (
			base.distance_squared_to(pond_spot as Vector3)
			< base.distance_squared_to(site_spot as Vector3)
		)
		else site_spot
	)


## A buildable cell in the nearest workable lithium pond, or null when there is none.
##
## "Workable" is charged, and not BELIEVED claimed (`_believes_pond_claimed`). A drained pond
## is dry ground with a surface on it, and a claimed one has no room for a second extractor
## (see WaterBody.extractor).
##
## TODO — the charge is still read live, so the bot knows a pond was drained out of its sight.
## A remembered charge would need a per-body memory the blackboard does not keep.
func _nearest_workable_pond_spot() -> Variant:
	if _bot.map == null:
		return null
	var dims: Vector2i = _dims_for_type(_extractor_type())
	var best: Variant = null
	var best_d: float = INF
	var base: Vector3 = _bot.base_centroid()
	var under_way: Array = _ponds_under_way()
	for body: WaterBody in _bot.map.water_bodies:
		if not is_instance_valid(body) or body.energy <= 0 or _believes_pond_claimed(body):
			continue
		# `_is_claimed_spot` is a RADIUS, and a pond is far wider than it — two jobs aimed at
		# different cells of one body both pass it. A reservoir is claimed whole or not at all.
		if under_way.has(body):
			continue
		var spot: Variant = _pond_spot_in(body, dims)
		if spot == null:
			continue
		var d: float = base.distance_squared_to(spot as Vector3)
		if d < best_d:
			best_d = d
			best = spot
	return best


## Every lithium pond an in-flight build order is already aimed into.
##
## The pond-side counterpart of `_types_under_way`: a body is only claimed on the tick an
## extractor is PLACED, so two builders ordered at one pond before either arrives would both
## be issued — and the engine then has to abandon the loser's order (Build.fulfill_action).
## Better not to spend the builder in the first place.
func _ponds_under_way() -> Array:
	var ponds: Array = []
	for unit: Commandable in _bot.get_units():
		if not _is_constructing(unit):
			continue
		var target: Variant = _construction_target(unit)
		if not (target is Vector3):
			continue
		var body: WaterBody = _bot.map.water_body_at_world(VU.in_xz(target as Vector3))
		if body != null and not ponds.has(body):
			ponds.append(body)
	return ponds


## The first EXPLORED cell of `a_body` an extractor actually fits on, or null.
##
## Asked through `EnergyExtractor.fits_in_pond` rather than this module's own `_placement_ok`,
## which would refuse every one of these cells for being submerged. `fits_in_pond` rather than
## `valid_placement` because the claim is judged by the caller, from belief.
func _pond_spot_in(a_body: WaterBody, a_dims: Vector2i) -> Variant:
	for cell: Vector2i in a_body.basin.covered_cells():
		if not a_body.is_shallow(cell):
			continue
		var world: Vector3 = _bot.map.grid_to_world(cell)
		if not _bot.has_explored(world):
			continue
		if _is_abandoned_spot(world) or _is_claimed_spot(world):
			continue
		if EnergyExtractor.fits_in_pond(
			CommandMessage.new(_bot.map, null, null, world), a_dims, true, true
		):
			return world
	return null


## The buildable type the bot works a reservoir with — whichever income structure it can
## build. Named rather than hardcoded so a faction with its own extractor piece works.
func _extractor_type() -> StringName:
	var types: Array = _bot.buildable_income_structure_types()
	return types[0] if not types.is_empty() else &""


## Closest explored extraction site the bot does not believe is worked, or null if there is none.
func _nearest_unclaimed_site() -> Entity:
	var base: Vector3 = _bot.base_centroid()
	var best: Entity = null
	var best_d: float = INF
	for n: Node in _bot.get_tree().get_nodes_in_group("extraction_site"):
		var dep: Entity = n as Entity
		var site: ExtractionSite = ExtractionSite.of(dep)
		if site == null or not _bot.has_explored(dep.global_position):
			continue
		if _believes_site_claimed(site, dep.global_position):
			continue
		if _is_abandoned_spot(dep.global_position):
			continue  # a site the builder could not finish a job on — see _abandoned_spots
		var d: float = base.distance_squared_to(dep.global_position)
		if d < best_d:
			best_d = d
			best = dep
	return best


## Whether the bot believes the site at `a_position` is already worked. What it can know is
## read live — its own extractor, or one standing in its vision — and anything else is what the
## blackboard remembers standing there, so a site taken out of sight still reads open until the
## bot looks (bot-architecture.md §Income is found by scouting).
func _believes_site_claimed(a_site: ExtractionSite, a_position: Vector3) -> bool:
	if _is_claim_known(a_site.extractor):
		return true
	# An extractor is placed concentric with its site, so a remembered one stands on its origin.
	return _believes_enemy_structure_where(
		func(a_at: Vector3) -> bool:
			return VU.in_xz(a_at).distance_to(VU.in_xz(a_position)) < Map.CELL_SIZE * 0.5
	)


## The pond counterpart of `_believes_site_claimed`. Any remembered structure in the water
## claims it, since an extractor is the only structure that may stand there.
func _believes_pond_claimed(a_body: WaterBody) -> bool:
	if _is_claim_known(a_body.extractor):
		return true
	return _believes_enemy_structure_where(
		func(a_at: Vector3) -> bool: return _bot.map.water_body_at_world(VU.in_xz(a_at)) == a_body
	)


## Whether `a_claimant` is a live extractor the bot may know about: its own, or one in its
## vision. Untyped because a deposit may hold a freed claimant.
func _is_claim_known(a_claimant: Variant) -> bool:
	if a_claimant == null or not is_instance_valid(a_claimant):
		return false
	var claimant: Commandable = a_claimant as Commandable
	return (
		claimant != null
		and (claimant.commander_id == _bot.id or _bot.has_vision_at(claimant.global_position))
	)


## Whether the blackboard remembers an enemy structure at a place `a_is_there` accepts.
func _believes_enemy_structure_where(a_is_there: Callable) -> bool:
	if _bot.blackboard == null:
		return false
	return _bot.blackboard.believed_structures().any(
		func(a_entry: CommanderBlackboard.Entry) -> bool:
			return a_is_there.call(a_entry.last_known_location)
	)


# ─── WHERE A BUILDING GOES ──────────────────────────────────────────────────────────
#
# THE OLD SCAN WAS A PREFERENCE IN WORLD COORDINATES, AND IT WAS THE LARGEST CONFOUNDER IN
# THE MEASUREMENT INSTRUMENT. `_find_build_spot` walked rings outward from the base and
# returned the FIRST valid cell, scanning `for dx` then `for dy` from -radius — so the cell
# it returned was always the one furthest toward -X, then -Z. On a provably point-symmetric
# map both commanders laid their bases out toward -X instead of toward ±X, stopped being
# mirror images at tick 60 and never were again; the resulting start-position bias was
# 16/16 with a mean material margin of +9,632 (gdd/systems/ai/selfplay-results-2026-09-06.md
# §The mechanism).
#
# WHAT REPLACES IT IS A SCORED COMPARISON EXPRESSED IN THE BOT'S OWN FRAME. Nothing below
# reads a world axis. The frame is (forward, right) where forward points at what the bot is
# oriented against — see _forward_direction — and every candidate is described by how far
# ALONG that axis it sits, how far LATERALLY, and how far from the base. The property this
# buys is EQUIVARIANCE, not symmetry: rotate the map and the placement rotates with it; put
# two bots in mirrored situations and they make mirrored choices. The layout itself is free
# to be lopsided, and is meant to be — production forward, everything else behind.
#
# NO RANDOM TIE-BREAK, deliberately. A draw from SU.rng would be reproducible across replays
# (which is the project's rule) but NOT mirror-consistent: two bots drawing from one shared
# stream in interleaved order get different numbers, so a tie broken by a draw is a tie
# broken by think order, which is the world-frame bug in another costume. Ties are broken by
# bot-frame coordinates instead, which mirror exactly.


## The best spot for a `a_type` structure, or null when nothing in range is placeable.
##
## Scores the whole candidate disc first (O(1) per cell) and validates in score order, so the
## expensive navigation checks run on the CHOSEN candidate rather than on every cell — and
## fall through to the next-best when one is refused.
##
## RESUMABLE: when the tick's allowance runs out part-way through the candidates it returns
## SEARCH_PENDING and keeps its place, and the next call for the same type carries on. Each
## candidate is still checked against the map as it is when checked, so a search that spans
## ticks can only rank on slightly old facts, never place on them.
func _find_build_spot(a_type: StringName) -> Variant:
	if _spot_search.get("type", &"") != a_type:
		_spot_search = _new_spot_search(a_type)
	var search: Dictionary = _spot_search
	# Rank first, a row of origins at a time; the checks start once every origin is scored.
	if not _continue_ranking(search["ranking"], _allowance - _work):
		return SEARCH_PENDING
	var candidates: PackedInt64Array = search["ranking"]["out"]
	var dims: Vector2i = search["dims"]
	var width: int = _bot.map.terrain_grid.grid_width()
	var cursor: int = search["cursor"]
	var start: int = cursor
	while cursor < candidates.size():
		# At least one candidate per call, so a tick whose other work already spent the
		# allowance still moves the search on rather than leaving it pending forever.
		if _work >= _allowance and cursor > start:
			search["cursor"] = cursor
			return SEARCH_PENDING
		var index: int = candidates[cursor] & 0xFFFFF
		cursor += 1
		_work += PLACEMENT_CHECK_WORK_UNITS
		var origin: Vector2i = Vector2i(index % width, index / width)
		if _placement_ok(_bot.map.footprint_centroid(origin, dims), dims, search["region"]):
			_spot_search = {}
			return _bot.map.footprint_centroid(origin, dims)
	_spot_search = {}
	return null


## A fresh build-spot search for `a_type`: its candidate ranking (not yet run) and what it
## needs to check the candidates.
func _new_spot_search(a_type: StringName) -> Dictionary:
	var dims: Vector2i = _dims_for_type(a_type)
	var anchor: Vector2 = VU.in_xz(_bot.base_centroid())
	return {
		"type": a_type,
		"dims": dims,
		"region": _home_region(),
		"cursor": 0,
		"ranking": _start_ranking(anchor, _forward_direction(anchor), _bearing_for(a_type), dims)
	}


## THE AXIS THE BOT ORIENTS AGAINST, as a unit vector from the base.
##
## Everything else in the placement model is measured against this, so it is the one thing
## that has to be a property of the bot's SITUATION rather than of the map's coordinates.
## In order of preference:
##
##   1. THE BELIEVED THREAT — the nearest enemy structure the bot has actually seen, else the
##      nearest enemy unit it remembers. Fog-limited on purpose, exactly as the attack
##      objective is (Bot §THE ATTACK OBJECTIVE, FOG-LIMITED): the bot orients against what it
##      has found, not against what is there.
##   2. THE MIDDLE OF THE MAP, before it has seen anything. An isometry of the map fixes the
##      map's centre, so base→centre transforms with the map — and it is a fair proxy for
##      "the contested ground" when nothing better is known.
##
## The remaining fallback is reached only when the base centroid sits exactly on the map
## centre with nothing believed, at which point the bot has no situation to be asymmetric
## about; it is the one line here that names an axis, and it is unreachable in play.
func _forward_direction(a_anchor: Vector2) -> Vector2:
	# A SENSE now (Bot.threat_direction), because the military stations the army by the same
	# axis; the rules above are its doc.
	return _bot.threat_direction(a_anchor)


## Which way `a_type` wants to sit on the forward axis, in cost per cell: positive pulls the
## building toward the threat, negative pushes it behind the base.
##
## Frontage forward, everything else behind — the whole of the model's asymmetry, and it is
## an asymmetry RELATIVE TO THE BOT rather than to the map. Classified by component rather
## than by a type list, like every other classification in this file.
func _bearing_for(a_type: StringName) -> float:
	return _bearing(_wants_frontage(a_type))


## Whether `a_type` belongs on the threat side of the base. Production does (the army comes
## out of it) and static defence does (the enemy walks into it). An AIRFIELD does not,
## whatever it trains: the aircraft parked on it are the fragile half, so the docking test is
## asked first because an airfield is also a producer. See
## gdd/systems/ai/squads-and-relations.md §Placement beyond open ground.
func _wants_frontage(a_type: StringName) -> bool:
	if a_type in _bot.buildable_docking_structure_types():
		return false
	return (
		a_type in _bot.buildable_production_structure_types()
		or a_type in _bot.buildable_defence_structure_types()
	)


func _bearing(a_wants_frontage: bool) -> float:
	return place_frontage_bias if a_wants_frontage else -place_shelter_bias


## A RESUMABLE RANKING of where a `a_dims` piece could stand around `a_anchor`, scored exactly as
## every building this bot places is. For a caller placing something other than a Build order —
## the deployment drops (BotDeployment) — so the bot has one notion of a good spot.
func start_spot_ranking(a_anchor: Vector2, a_dims: Vector2i, a_is_production: bool) -> Dictionary:
	return _start_ranking(a_anchor, _forward_direction(a_anchor), _bearing(a_is_production), a_dims)


## Carry `a_ranking` on for at most `a_allowance` work units and return the units spent. It is
## finished when `a_ranking["done"]`, and `a_ranking["out"]` then holds the candidates best-first.
func continue_spot_ranking(a_ranking: Dictionary, a_allowance: int) -> int:
	var before: int = _work
	_continue_ranking(a_ranking, a_allowance)
	return _work - before


## The lowest and the highest cost a ranked candidate can have, as (ideal, worst): the ideal sits
## as close as the search allows, fully along its bearing, in open ground; the worst at the edge
## of the search, fully against it, with one cell of clearance. A caller relaxing a threshold
## from one to the other has spanned every spot the ranking could offer.
func spot_cost_bounds(a_is_production: bool) -> Vector2:
	var bearing: float = absf(_bearing(a_is_production))
	var ideal: float = (
		minf(
			SEARCH_MIN_RING * (COMPACTNESS_WEIGHT - bearing),
			SEARCH_MAX_RING * (COMPACTNESS_WEIGHT - bearing)
		)
		- place_corridor_weight * CORRIDOR_CAP_CELLS
	)
	var worst: float = SEARCH_MAX_RING * (COMPACTNESS_WEIGHT + bearing) - place_corridor_weight
	return Vector2(ideal, worst)


## The cost a ranked candidate was scored at, as _pack quantised it.
static func ranked_cost(a_packed: int) -> float:
	return float(((a_packed >> 44) & 0x3FFF) - 8192) / 100.0


## The footprint origin a ranked candidate stands for, on a grid `a_grid_width` cells wide.
static func ranked_origin(a_packed: int, a_grid_width: int) -> Vector2i:
	var index: int = a_packed & 0xFFFFF
	return Vector2i(index % a_grid_width, index / a_grid_width)


## Every candidate cell in the search annulus, scored and ordered best-first.
##
## Each entry is `[quantised cost, quantised -along, quantised lateral, world position]` and
## the first three are INTEGERS. That is what makes the ordering mirror-exact rather than
## merely mirror-close: two bots in mirrored situations compute scores that agree to within a
## few ULPs, and comparing the raw floats would let the last bit decide a tie. Quantising to
## SCORE_QUANTUM collapses that noise, and `(cost, along, lateral)` is a total order in the
## BOT'S frame — `along` and `lateral` are preserved by the mirror, so corresponding
## candidates land at corresponding ranks in both bots' lists.
##
## THE COST, all in cells and all bot-relative:
##
##   + COMPACTNESS_WEIGHT × distance from the base   — the ruler; sprawl is what everything
##                                                     else is priced against
##   − bearing × distance along the forward axis     — production forward, the rest behind
##   − place_corridor_weight × open ground around it — don't pinch your own lanes
func _scored_candidates(
	a_anchor: Vector2, a_forward: Vector2, a_bearing: float, a_dims: Vector2i
) -> PackedInt64Array:
	var ranking: Dictionary = _start_ranking(a_anchor, a_forward, a_bearing, a_dims)
	_continue_ranking(ranking, BotJob.UNLIMITED_WORK_UNITS)
	return ranking["out"]


## The state of one ranking: what every candidate is scored against, fixed when it starts, the
## row of origins it has reached, and the candidates found so far. See _scored_candidates.
func _start_ranking(
	a_anchor: Vector2, a_forward: Vector2, a_bearing: float, a_dims: Vector2i
) -> Dictionary:
	var map: Map = _bot.map

	# A CANDIDATE IS A FOOTPRINT ORIGIN, NOT A CELL, and that distinction is load-bearing.
	# Map.footprint_origin resolves an EVEN footprint by rounding in absolute grid coordinates,
	# so two mirror-image cell centres do NOT resolve to mirror-image footprints — it is the
	# same world-frame preference as the old ring scan, one layer down, and it showed up as a
	# one-cell residual between two otherwise perfect mirror layouts. Origins are immune: the
	# set of origins for a `dims` footprint is carried onto itself by the map's reflection, so
	# their centroids reflect exactly onto each other.
	var seed_origin: Vector2i = map.footprint_origin(a_anchor, a_dims)
	# The origin→world map is affine, so it is read ONCE off three probes rather than called
	# per candidate: footprint_centroid averages cell centres sampled off the heightmap, and
	# six hundred of those was most of what a decision cost. Only XZ matters to the score.
	var world_seed: Vector2 = VU.in_xz(map.footprint_centroid(seed_origin, a_dims))
	return {
		"forward": a_forward,
		"right": Vector2(-a_forward.y, a_forward.x),
		"bearing": a_bearing,
		"dims": a_dims,
		"seed_origin": seed_origin,
		"seed_offset": world_seed - a_anchor,
		"basis_x":
		VU.in_xz(map.footprint_centroid(seed_origin + Vector2i(1, 0), a_dims)) - world_seed,
		"basis_z":
		VU.in_xz(map.footprint_centroid(seed_origin + Vector2i(0, 1), a_dims)) - world_seed,
		"row": -SEARCH_MAX_RING - 1,
		"out": PackedInt64Array(),
		"done": false,
	}


## Score origins row by row until every row is done — sorting the result best-first and
## returning true — or `a_allowance` more work units are spent (false, to be continued). At
## least one row per call, so the ranking always moves on.
func _continue_ranking(a_ranking: Dictionary, a_allowance: int) -> bool:
	if a_ranking["done"]:
		return true
	var grid: TerrainGrid = _bot.map.terrain_grid
	var width: int = grid.grid_width()
	var depth: int = grid.grid_depth()
	var min_sq: float = float(SEARCH_MIN_RING * SEARCH_MIN_RING)
	var max_sq: float = float(SEARCH_MAX_RING * SEARCH_MAX_RING)
	var dims: Vector2i = a_ranking["dims"]
	var seed_origin: Vector2i = a_ranking["seed_origin"]
	var forward: Vector2 = a_ranking["forward"]
	var right: Vector2 = a_ranking["right"]
	var bearing: float = a_ranking["bearing"]
	var basis_x: Vector2 = a_ranking["basis_x"]
	var out: PackedInt64Array = a_ranking["out"]
	var budget_end: int = _work + a_allowance
	var dz: int = a_ranking["row"]
	var first: int = dz
	while dz <= SEARCH_MAX_RING + 1:
		if _work >= budget_end and dz > first:
			a_ranking["row"] = dz
			a_ranking["out"] = out
			return false
		var row: Vector2 = a_ranking["seed_offset"] + a_ranking["basis_z"] * float(dz)
		var origin_z: int = seed_origin.y + dz
		dz += 1
		if origin_z < 0 or origin_z + dims.y > depth:
			continue
		for dx: int in range(-SEARCH_MAX_RING - 1, SEARCH_MAX_RING + 2):
			# The DISC is measured in world space rather than in cell indices, so the candidate set
			# is itself mirror-exact: footprint centroids reflect onto footprint centroids.
			var offset: Vector2 = row + basis_x * float(dx)
			var radial_sq: float = offset.length_squared()
			if radial_sq < min_sq or radial_sq > max_sq:
				continue
			var origin_x: int = seed_origin.x + dx
			if origin_x < 0 or origin_x + dims.x > width:
				continue
			_work += RANK_ORIGIN_WORK_UNITS
			# The TIGHTEST point of the footprint is what says whether building here pinches a
			# lane, and a min over the footprint is mirror-invariant where a single cell's reading
			# is not. It doubles as the passability screen: distance_to_obstacle is 0 for an
			# impassable cell, so a zero here means some cell of the footprint is steep, flooded or
			# already built on, and nothing further need be computed for it.
			var clearance: int = CORRIDOR_CAP_CELLS
			for fx: int in dims.x:
				for fz: int in dims.y:
					clearance = mini(
						clearance, grid.distance_to_obstacle(Vector2i(origin_x + fx, origin_z + fz))
					)
			if clearance <= 0:
				continue
			var along: float = offset.dot(forward)
			var cost: float = (
				COMPACTNESS_WEIGHT * sqrt(radial_sq)
				- bearing * along
				- place_corridor_weight * float(clearance)
			)
			out.append(_pack(cost, along, offset.dot(right), origin_z * width + origin_x))
	out.sort()
	_work += out.size() * CANDIDATE_WORK_UNITS
	a_ranking["out"] = out
	a_ranking["done"] = true
	return true


## ONE SORTABLE INTEGER PER CANDIDATE: cost, then distance along the forward axis, then
## lateral offset, then the cell it came from — packed most-significant-first so the NATIVE
## ascending sort IS the preference order. A `sort_custom` over the same numbers costs a
## GDScript call per comparison, which was measurable next to everything else here.
##
## THE QUANTISATION IS WHAT MAKES THE ORDER MIRROR-EXACT rather than merely mirror-close. Two
## bots in mirrored situations compute scores that agree only to within a few ULPs, and
## comparing raw floats would let the last bit decide a tie; at 1/100 of a cell that noise is
## gone. `(along, lateral)` is the offset in another basis, so no two distinct cells share it
## and the order is TOTAL — which is what makes corresponding candidates land at
## corresponding ranks in both bots' lists. The cell index rides in the low 20 bits purely so
## the winner can be turned back into a position.
static func _pack(a_cost: float, a_along: float, a_lateral: float, a_cell_index: int) -> int:
	var cost: int = clampi(roundi(a_cost * 100.0) + 8192, 0, 16383)
	var along: int = clampi(roundi(-a_along * 100.0) + 2048, 0, 4095)
	var lateral: int = clampi(roundi(a_lateral * 100.0) + 2048, 0, 4095)
	return (cost << 44) | (along << 32) | (lateral << 20) | (a_cell_index & 0xFFFFF)


## THE REGION OF THE MAP THE BOT LIVES ON, as a TerrainGrid component id.
##
## Read off where the bot's own units are STANDING rather than off the base centroid, which
## is usually inside a building and therefore on no region at all. The modal region over the
## units is order-independent (so it mirrors) and means the right thing: the ground the army
## is on is the ground a new building has to stay reachable from. Falls back to the biggest
## region on the map when the bot owns no units yet.
func _home_region() -> int:
	var grid: TerrainGrid = _bot.map.terrain_grid
	var tally: Dictionary = {}
	for u: Commandable in _bot.get_units():
		var region: int = grid.component_at(_bot.map.world_to_grid(VU.in_xz(u.global_position)))
		if region >= 0:
			tally[region] = int(tally.get(region, 0)) + 1
	var best: int = -1
	var best_count: int = 0
	for region: int in tally:
		var count: int = int(tally[region])
		if count > best_count or (count == best_count and region < best):
			best_count = count
			best = region
	return best if best >= 0 else grid.largest_component()


## The widest unit the bot keeps its base passable for: the largest navigation class there is,
## so no unit any faction fields is ever sealed out of a bot base or off one of its buildings.
## A bot-only rule for now; human placement asks only rules 1 and 2 (NavPlacement §Rule 3).
const PLACEMENT_NAV_CLASS: int = NavAgentClass.Size.LARGE


## Whether a structure of `a_dims` centred at `a_world` may actually be built there.
##
## Cheapest test first: the geometry (in bounds, unoccupied, flat), then the written-off
## list, then the two NAVIGATION rules, which live in the map layer because they are facts
## about the map rather than bot preferences — see NavPlacement.
##
## EVERY structure the bot places is required to keep a side on the navmesh, not only the
## ones that train units. A building nothing can walk to cannot be repaired, garrisoned or
## deposited into either, so there is no kind of building the bot wants sealed in; the
## narrower "production only" reading of the rule is available to other callers as
## NavPlacement.accepts' `a_needs_access` flag.
func _placement_ok(a_world: Vector3, a_dims: Vector2i, a_region: int = -1) -> bool:
	if not Structure.valid_placement(
		CommandMessage.new(_bot.map, null, null, a_world), a_dims, false
	):
		return false
	if _is_abandoned_spot(a_world):
		return false
	if _is_claimed_spot(a_world):
		return false
	var footprint: Array = _bot.map.footprint_cells(VU.in_xz(a_world), a_dims)
	var grid: TerrainGrid = _bot.map.terrain_grid
	return (
		NavPlacement.accepts(grid, footprint, true, a_region)
		and NavPlacement.accepts_for_class(grid, footprint, PLACEMENT_NAV_CLASS, true)
	)


## Footprint dimensions for a buildable type, read off its build-preview instance
## (the same Structure component Build inspects). Falls back to 2×2.
func _dims_for_type(a_type: StringName) -> Vector2i:
	var tool: Tool = Tool.for_type(a_type)
	if tool != null:
		var preview: Node = _bot.get_build_preview_instance(tool)
		var s: Structure = (
			preview.get_node_or_null("Structure") as Structure if preview != null else null
		)
		if s != null:
			return s.dimensions
	return Vector2i(2, 2)
