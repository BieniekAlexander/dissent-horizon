class_name BotDifficulty
extends RefCounted

## HOW HARD A BOT PLAYS, as data rather than as branches.
##
## One instance per `PlayerSlot.Difficulty`, handed to the brain at attach time and read by
## the managers. Before it existed, `difficulty` was consulted in exactly two places and
## every module carried a comment promising a knob later — so there was nowhere to put the
## outcome of any tuning, and every improvement shipped at one strength for everybody.
##
## **NUMBERS, NOT BRANCHES, AND THAT IS THE WHOLE DESIGN.** The tiers are meant to be
## SEARCHED — the intended end state is adversarial self-play tuning them (see
## gdd/systems/ai/bot-roadmap.md §The training harness), and the discipline that makes such a
## search mean anything is holding every other behaviour equal while varying one parameter. A
## tier that differed by `if difficulty == HARD` cannot be held equal, cannot be interpolated,
## and cannot be reported as "this number moved". So a handicap that cannot be expressed as a
## field here is a signal that the manager needs a parameter, not that this class needs a
## branch.
##
## `may_attack` is the one boolean, and it earns it: PASSIVE is a KIND of opponent rather than
## a weaker one.
##
## RefCounted rather than a Resource: these are code-owned defaults with no per-scenario
## authoring story yet, and a Resource would invite an inspector slot that nothing fills.

#region Fields
## HOW OFTEN EACH KIND OF DECISION IS REVISITED, in seconds — the bot's REACTION TIME, split
## by what is being reacted to. Each is the period of a group of BotScheduler jobs (see
## BotBrain.register_jobs), and a slow period is the most human-feeling handicap available: a
## slow bot notices an attack late and answers it late, which reads as being out-thought rather
## than as being cheated.
##
## Combat decisions — the army's posture and objective, retargeting, and momentum.
var combat_period_seconds: float = 0.5
## The economy, production, opportunistic errands and sanctions.
var strategy_period_seconds: float = 0.5
## Scouting: updating what has been seen, and dispatching scouts.
var scout_period_seconds: float = 0.5

## Combat units wanted before the army commits to an attack. The aggression dial.
var army_commit_threshold: int = 3

## Cheapest unit worth pulling out of a losing fight, in energy. -1 never retreats anything;
## 0 retreats everything.
var preserve_min_cost: int = 250

## How much better another target must score before a unit switches to it — COMMITMENT. A
## high margin means the bot will not micro away from a trade it has started, which is what
## separates a deliberate opponent from a jittery one.
var retarget_switch_margin: float = 1.3

## How many units the bot is willing to have away from the fight, scouting. 0 means it never
## scouts and plays blind.
##
## A REAL RAMP, not a flag. It shipped as 1 for every tier below IMPOSSIBLE, which made it a
## constant wearing a parameter's clothes — and one scout is badly under-provisioned now that
## the ATTACK objective is fog-limited (Bot.nearest_believed_enemy_structure_position): a bot
## that has not found the opponent's base has no offensive at all, so how many units it will
## spend looking is now one of the strongest handicaps in this table rather than a detail.
##
## It remains a CEILING. `BotScout._scouting_is_worth_it` prices each additional scout
## against the information it buys, and the value of the n-th scout is divided by n, so a
## larger allowance is permission rather than an instruction — a bot that already knows where
## everything is will not use it.
var scout_unit_budget: int = 2

## Energy banked before the bot will spend on expanding capacity. A high reserve plays
## greedily-safe; a low one commits early.
var economy_reserve: int = 600

## Whether this bot ever takes offensive action at all. False for PASSIVE: it still builds,
## trains and defends itself, but never marches on the player and never spends a sanction
## offensively.
var may_attack: bool = true

# ── THE ECONOMY AND THE PRODUCTION MIX ──────────────────────────────────────────────
# The roadmap's §1: the opening is a LADDER, and a ladder is a script a player learns. These
# do not convert the ladder into a comparison — that waits on the energy-versus-dominion
# question — but they are the numbers the ladder's shape is made of, so a search can ask
# "how much capacity, how fast, weighted how" without the ordering being rewritten.

## How many construction jobs the bot will keep in flight at once, and therefore how many
## builders it wants. **-1 is UNCAPPED** — the same sentinel `production_structure_cap` uses.
## Higher (and -1 highest) = expands faster, and pulls proportionally more fighters off the
## line to do it. 0 and below, other than the sentinel, is treated as 1.
##
## It was 1 on EVERY tier until 2026-09-12, which is a constant wearing a parameter's clothes
## — and a visible one: a Colonial opening pairs two Servants, so the second stood idle for
## the whole match with nothing else in the bot willing to claim an unarmed unit.
var build_concurrency: int = 1

## Ceiling on how many production structures the bot plans to own, counting the buildable
## types it has put up (including ones still under construction). -1 is UNCAPPED, which is
## what the bot does today: it keeps adding capacity for as long as it is in surplus.
## Higher (and -1 highest) = greedier throughput at the cost of army now.
var production_structure_cap: int = -1

## HOW MANY INCOME STRUCTURES THE BOT WANTS STANDING before it adds production capacity,
## when nothing is pressing. Higher = GREEDIER: more of the opening goes on extractors and
## less on the buildings that make army. 0 reproduces the pre-2026-09-05 opening, which
## spent the whole starting grant on throughput and finished its first extractor at 125 s.
##
## **NOT A BUILD ORDER — a target the game bends.** BotEconomy.effective_income_target
## multiplies it by BotEconomy.safety(), so it is what the bot wants when it is SAFE and
## collapses toward 0 as the bot comes under pressure: greed when safe, capacity when
## threatened. Safety can only ever reduce it, never raise it above the value set here.
##
## **ONE OF TWO DEFAULTS IN THIS CLASS THAT DO NOT REPRODUCE THE OLD PLAY** (the other is
## reinforce_fraction), deliberately: 1
## means "one extractor before the first barracks", which is the ordering the opening
## question was about. Every other field added for the search ships at the value that
## changes nothing (see §The tiers ship flat in bot-parameter-space.md).
var income_structure_target: int = 1

## HOW READILY THE BOT ANSWERS STATIC-DEFENCE DEMAND — a propensity on the value × vulnerability
## read of its own regions (BotEconomy._defence_demand), held against a turret's cost: 1 buys
## where the ground is worth the gun, 0 never buys one, higher buys sooner. Replaces the count
## of turrets wanted, which bought three in a clump in the opening before anything had been
## seen (REJECTED, world-model.md §L3). Higher = more towers, not more skill.
var defence_propensity: float = 1.0

## HOW MUCH BETTER A LOCKED UNIT MUST BE before the bot buys the structure that unlocks it:
## the best composition value (Bot.unit_composition_value, against the enemy it believes in)
## among units behind one tech structure, over the best it can train today, must reach this
## ratio. 1.0 techs the moment anything better exists; 3.0 never techs. The ratio is on
## STRENGTH against the current enemy, not strength per energy, because a higher-tech unit is
## generally stronger and seldom cheaper per point — and the margin is what represents the
## overhead of the investment (the building's price and its build time) without pricing it.
## The structures a tech building unlocks are not scored: a Bombard behind an Operations
## Center is worth nothing to this ratio. See gdd/systems/ai/bot-architecture.md §The tech rung.
var tech_value_margin: float = 1.3

## How many non-combat utility units (the Colonial Stock Truck and its like) the bot keeps
## alive. They build, capture and scout rather than fight, so a higher cap buys map control
## and the dominion loop with energy that would otherwise be army.
##
## A SAFETY CEILING now, not the decision: BotProduction._utility_demand_for sizes the count
## to the live errands (one builder per concurrent build job, one carrier per capturable
## cluster, plus a spare) and this bounds the answer. Raising it permits a bigger fleet when
## there is work for one; it no longer instructs the bot to build one.
var utility_unit_cap: int = 3

## How much an enemy STRUCTURE counts toward production demand, against 1.0 for an enemy
## unit. Raising it builds more of what razes a base; lowering it builds purely against the
## enemy army. The long game against the immediate one, as one number.
var structure_demand_weight: float = 0.4

## How fast a threat stops being worth countering once the army already answers it —
## demand is divided by `1 + coverage × this`. 0 never saturates, so the bot masses the
## single best counter forever; higher diversifies sooner, and over-diversifies eventually.
var demand_coverage_falloff: float = 1.0

# ── WHERE A BUILDING GOES ───────────────────────────────────────────────────────────
# The placement model's three weights (BotEconomy §WHERE A BUILDING GOES). All three are
# costs per CELL, measured against compactness — the pull back toward the base centroid —
# which is deliberately NOT a field: the score is only ever compared against other
# candidates for the same building, so multiplying every weight by one factor changes no
# decision and one term has to be the ruler. Same argument that keeps THREAT out of the
# retarget mix below.

## How far toward the BELIEVED THREAT a production structure wants to sit, per cell, against
## compactness = 1.0. Production is where the army comes from, so pushing it up the threat
## axis shortens every reinforcement walk; the cost is a building closer to what is coming.
## Range [0.0, 1.5]. Above 1.0 the directional reward outruns the sprawl cost and the bot
## builds at the far edge of its search radius; 0.0 makes production directionless.
var place_frontage_bias: float = 0.6

## How far AWAY from the believed threat everything else wants to sit, on the same scale —
## infrastructure, the dominion structure, anything the bot is not fighting out of. Range
## [0.0, 1.5]; higher tucks support further behind the base, 0.0 makes it directionless.
var place_shelter_bias: float = 0.6

## What keeping its own lanes open is worth, per cell of clearance around the spot (capped at
## four). The hard constraint already refuses a placement that SPLITS the map; this is the
## softer preference that stops the bot squeezing a corridor down on the way there. Range
## [0.0, 3.0]; higher = airier bases, 0.0 packs buildings against terrain and each other.
var place_corridor_weight: float = 0.8

# ── THE ARMY ────────────────────────────────────────────────────────────────────────

## Army value, as a multiple of the believed enemy's, at which a wave launches. This is the
## real commit rule (`army_commit_threshold` is the cruder unit COUNT beside it); lower is
## more aggressive, and below 1 attacks while behind.
var attack_value_ratio: float = 1.3

## THE HUMILITY PRIOR: the fraction of our own army the bot assumes the unseen enemy has,
## unless it has actually seen more. Under fog it compares its whole army to the seen slice
## of theirs, so without this it reads phantom leads. Lower = credulous and reckless; higher
## = it needs a real advantage before it believes in one.
var assumed_enemy_parity: float = 0.85

## Fraction of its launch value the army may be reduced to before a wave is called off —
## and only then if momentum says it is still bleeding. 0 never retreats an army; 1.0 leaves
## at the first loss taken while losing. Higher = better at cutting its losses.
var wave_abort_fraction: float = 0.70

## How much of the wave's launch value the staged reserve must be worth before it is sent
## to join the wave as a body. 0 is the trickle the bot shipped with — every new unit walks
## to the front alone — and higher holds reinforcements back longer for a bigger second
## push. THE SECOND DEFAULT THAT DOES NOT REPRODUCE THE OLD PLAY (with
## income_structure_target), deliberately: the trickle is the behaviour being removed, and
## 0 stays reachable for an A/B. See gdd/systems/ai/squads-and-relations.md.
var reinforce_fraction: float = 0.5

## How many squads the military may run at once — the control groups a player plays
## through. 1 is one body: every reinforcement walks to the front alone, and the reserve
## never stages (the trickle, whatever `reinforce_fraction` says). 2 is wave and reserve. 3
## adds the guard: the reserve turns to a threatened structure while the wave is away. −1
## lifts the cap. A bot that manoeuvres a hundred units independently is optimal and
## unbelievable; the cap is a handicap that reads as human and bounds the think cost.
## See gdd/systems/ai/squads-and-relations.md §Squads.
var squad_cap: int = 2

## How close (world units) an enemy must come to an owned structure to count as pressuring
## the base, pulling the army home and pointing sanctions at it. Higher answers harassment
## further out and turtles more; low enough and a raid inside the base is ignored.
var defend_threat_radius: float = 10.0

# ── VARIETY ─────────────────────────────────────────────────────────────────────────
# Two matches on one map used to play out identically because every decision was a pure
# function of state and these parameters. Both knobs below are drawn from the BOT'S OWN seeded
# generator (BotBrain.rng), so a match is still reproducible from its seed and a different
# seed is a different opponent. See gdd/systems/ai/bot-randomness.md.

## How far this bot's PERSONALITY may stray from its tier: the standard deviation, as a
## fraction of each field's range in SEARCH_RANGES, of a draw made once per match for every
## searchable field. 0 plays the tier exactly — the deterministic bot — and is what a
## controlled experiment should set. A sentinel value (−1 uncapped, PASSIVE's 9999) is never
## moved. THE THIRD DEFAULT THAT DOES NOT REPRODUCE THE OLD PLAY, deliberately.
var personality_spread: float = 0.15

## How willing a scored decision is to take an option that is NOT the best: an option within
## this fraction of the best score is a live alternative (BotSampling). 0 is the argmax every
## scored module used before. Read by BotProduction (which unit), BotOpportunist (which errand
## first) and BotScout (which unit scouts); never by placement, which must stay mirror-exact.
var decision_temperature: float = 0.1

## The range each searchable field may take — what a personality draw stays inside, and the
## same bounds bot-parameter-space.md gives a tuning run. A field absent here is never
## jittered: the periods (reaction time is the tier's identity), the booleans, and the two
## variety knobs themselves. A value OUTSIDE its range is a sentinel and is left alone.
const SEARCH_RANGES: Dictionary = {
	"army_commit_threshold": [1, 12],
	"preserve_min_cost": [0, 800],
	"retarget_switch_margin": [1.0, 3.0],
	"scout_unit_budget": [0, 4],
	"economy_reserve": [0, 1500],
	"build_concurrency": [1, 4],
	"production_structure_cap": [1, 8],
	"utility_unit_cap": [0, 6],
	"income_structure_target": [0, 8],
	"defence_propensity": [0.0, 3.0],
	"tech_value_margin": [1.0, 3.0],
	"structure_demand_weight": [0.0, 1.0],
	"demand_coverage_falloff": [0.0, 4.0],
	"attack_value_ratio": [0.8, 2.5],
	"assumed_enemy_parity": [0.0, 1.5],
	"wave_abort_fraction": [0.0, 1.0],
	"reinforce_fraction": [0.0, 1.0],
	"squad_cap": [1, 3],
	"defend_threat_radius": [3.0, 30.0],
	"retarget_weight_effectiveness": [0.0, 3.0],
	"retarget_weight_finishability": [0.0, 3.0],
	"retarget_weight_proximity": [0.0, 3.0],
	"place_frontage_bias": [0.0, 1.5],
	"place_shelter_bias": [0.0, 1.5],
	"place_corridor_weight": [0.0, 3.0],
}

# ── PER-UNIT TARGETING ──────────────────────────────────────────────────────────────
# The retarget signal mix, which BotTargeting's own doc names as a natural thing for the
# harness to search. THREAT has no field and is the unit of the scale: the score is compared
# against the current target's score times `retarget_switch_margin`, so multiplying every
# weight by the same factor changes nothing and one of the four has to be the ruler.

## Weight on MATCHUP (the damage multiplier this unit gets against the candidate), relative
## to threat = 1.0. Higher makes a unit seek out what it is good against.
var retarget_weight_effectiveness: float = 1.0

## Weight on FINISHABILITY (how much of the candidate's HP is already gone), relative to
## threat = 1.0. Higher makes the bot finish wounded targets rather than spread damage.
var retarget_weight_finishability: float = 1.0

## Weight on PROXIMITY (1/(1+distance)), relative to threat = 1.0. Higher makes a unit take
## whatever is nearest instead of walking to a better trade.
var retarget_weight_proximity: float = 0.5
#endregion


#region Tiers
## The tier table, as a monotone ramp from EASY to IMPOSSIBLE.
##
## THESE VALUES ARE PLACEHOLDERS chosen by hand, and nothing should be balanced against them
## until a search has run — see the TODO in bot-roadmap.md §Difficulty first. What is settled
## is WHICH knobs exist and which direction each one means; what is not is any number here.
##
## THE KNOBS ADDED FOR THE SEARCH SHIP FLAT, at the value that reproduces the play the bot
## had before they were fields, and that is a deliberate position rather than an omission.
## The seven knobs above are already an unmeasured hand-ramp the note warns against
## balancing on; hand-ramping twelve more would multiply exactly the guesswork the search
## exists to remove, and would make opening a knob indistinguishable from changing the
## game. A constant is monotone, so the ramp property below still holds, and each field's
## doc comment records which direction is "harder" so a search — or a later hand ramp —
## knows which way to move it. See gdd/systems/ai/bot-parameter-space.md.
static func for_tier(a_tier: PlayerSlot.Difficulty) -> BotDifficulty:
	var config := BotDifficulty.new()
	match a_tier:
		PlayerSlot.Difficulty.PASSIVE:
			# Minimally active, and never an attacker. It thinks slowly, keeps its economy going,
			# defends what it owns, and scouts not at all — a sparring partner rather than scenery,
			# which is what an INERT brain made it.
			config.set_all_periods(2.0)
			config.army_commit_threshold = 9999
			config.preserve_min_cost = -1
			config.retarget_switch_margin = 3.0
			config.scout_unit_budget = 0
			config.economy_reserve = 900
			config.build_concurrency = 1
			config.squad_cap = 1
			config.may_attack = false
			# A sparring partner is predictable on purpose: no personality, no sampling.
			config.personality_spread = 0.0
			config.decision_temperature = 0.0
		PlayerSlot.Difficulty.EASY:
			config.set_all_periods(1.5)
			config.army_commit_threshold = 8
			config.preserve_min_cost = -1
			config.retarget_switch_margin = 2.5
			config.scout_unit_budget = 1
			config.economy_reserve = 900
			config.build_concurrency = 1
			config.squad_cap = 1
		PlayerSlot.Difficulty.MEDIUM:
			config.set_all_periods(0.667)
			config.army_commit_threshold = 5
			config.preserve_min_cost = 250
			config.retarget_switch_margin = 1.6
			config.scout_unit_budget = 2
			config.economy_reserve = 600
			config.build_concurrency = 2
			config.squad_cap = 2
		PlayerSlot.Difficulty.HARD:
			config.set_all_periods(0.4)
			config.army_commit_threshold = 3
			config.preserve_min_cost = 0
			config.retarget_switch_margin = 1.3
			config.scout_unit_budget = 3
			config.economy_reserve = 450
			config.build_concurrency = 3
			config.squad_cap = 3
		PlayerSlot.Difficulty.IMPOSSIBLE:
			# TODO: the brief is "a human will never realistically beat it", which wants
			# frame-perfect micro and an execution layer these parameters cannot express. This is
			# the fast end of the same ramp, not that. See bot-roadmap.md §Difficulty first.
			config.set_all_periods(0.1)
			config.army_commit_threshold = 2
			config.preserve_min_cost = 0
			config.retarget_switch_margin = 1.1
			config.scout_unit_budget = 4
			config.economy_reserve = 300
			# Uncapped: it builds with everything it can spare.
			config.build_concurrency = -1
			config.squad_cap = -1
	return config


#endregion


#region Personality
## A copy of this config with every field in SEARCH_RANGES moved by a Gaussian draw of
## `a_spread` × the field's range, clamped to the range, ints rounded. The draw order is the
## table's order, so one seed is one personality. No generator or no spread: an exact copy.
func jittered(a_rng: RandomNumberGenerator, a_spread: float) -> BotDifficulty:
	var out: BotDifficulty = copied()
	if a_rng == null or a_spread <= 0.0:
		return out
	for field: String in SEARCH_RANGES:
		var lo: float = float(SEARCH_RANGES[field][0])
		var hi: float = float(SEARCH_RANGES[field][1])
		var current: Variant = out.get(field)
		if float(current) < lo or float(current) > hi:
			continue  # a sentinel, outside the range on purpose
		var drawn: float = clampf(float(current) + a_rng.randfn(0.0, a_spread * (hi - lo)), lo, hi)
		out.set(field, roundi(drawn) if typeof(current) == TYPE_INT else drawn)
	return out


## Set each named field from a JSON-shaped dictionary — a roster vector, a scenario's
## overrides, a harness config — coercing JSON's one number type to whatever the field holds
## (`3.0` sets an int field, `1` sets a bool). Returns "" when every key named a field, else
## a message naming the first that did not, with NOTHING applied: the dictionary is authored
## content, refused whole at the boundary rather than half-applied.
func apply_overrides(a_overrides: Dictionary) -> String:
	var fields: Dictionary = _script_fields()
	for key: Variant in a_overrides:
		if not fields.has(str(key)):
			return "BotDifficulty has no field '%s'" % str(key)
	for key: Variant in a_overrides:
		set(str(key), _coerced(a_overrides[key], fields[str(key)]))
	return ""


## Script variable name → Variant.Type, the set the harness reads and writes.
func _script_fields() -> Dictionary:
	var out: Dictionary = {}
	for property: Dictionary in get_property_list():
		if property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			out[property["name"]] = property["type"]
	return out


static func _coerced(value: Variant, type: int) -> Variant:
	match type:
		TYPE_INT:
			return int(value)
		TYPE_FLOAT:
			return float(value)
		TYPE_BOOL:
			return bool(value)
	return value


## A field-for-field copy, over the script variables — the same set the self-play harness
## reads and writes, so a field added to this class is copied the moment it exists.
func copied() -> BotDifficulty:
	var out := BotDifficulty.new()
	for property: Dictionary in get_property_list():
		if property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			out.set(property["name"], get(property["name"]))
	return out


#endregion


#region Queries
## Set every decision period to `a_seconds`. The tiers ship with one period for everything —
## the reaction time each had when there was a single think interval — so splitting the
## periods changed no tier's play; tuning them apart is the search's job.
func set_all_periods(a_seconds: float) -> void:
	combat_period_seconds = a_seconds
	strategy_period_seconds = a_seconds
	scout_period_seconds = a_seconds


## Whether a unit costing `a_cost` energy is worth pulling out of a losing fight.
func preserves_unit_costing(a_cost: int) -> bool:
	return preserve_min_cost >= 0 and a_cost >= preserve_min_cost


## Whether `a_concurrency` places no ceiling on concurrent construction.
##
## STATIC, and taking the value rather than reading the field, because the managers are pushed
## individual ints rather than the config object (BotBrain._apply_config) — the harness
## reflects over these fields, so they stay plain typed vars. This keeps the sentinel's meaning
## in ONE place instead of a bare `< 0` at each call site, the same way preserves_unit_costing
## keeps `preserve_min_cost`'s.
static func is_build_uncapped(a_concurrency: int) -> bool:
	return a_concurrency < 0


## How many jobs may run at once, for a caller that needs a number rather than a test. The
## sentinel has no finite answer, so an uncapped caller must ask is_build_uncapped first.
static func build_slots(a_concurrency: int) -> int:
	return maxi(1, a_concurrency)


## Whether `a_cap` places no ceiling on how many squads the military runs. Static for the
## same reason as is_build_uncapped: the military is pushed the int, not the config.
static func is_squad_uncapped(a_cap: int) -> bool:
	return a_cap < 0
#endregion
