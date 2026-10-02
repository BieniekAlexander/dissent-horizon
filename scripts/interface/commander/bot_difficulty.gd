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
## **THE ONE DEFAULT IN THIS CLASS THAT DOES NOT REPRODUCE THE OLD PLAY**, deliberately: 1
## means "one extractor before the first barracks", which is the ordering the opening
## question was about. Every other field added for the search ships at the value that
## changes nothing (see §The tiers ship flat in bot-parameter-space.md).
var income_structure_target: int = 1

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

## How close (world units) an enemy must come to an owned structure to count as pressuring
## the base, pulling the army home and pointing sanctions at it. Higher answers harassment
## further out and turtles more; low enough and a raid inside the base is ignored.
var defend_threat_radius: float = 10.0

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
			config.may_attack = false
		PlayerSlot.Difficulty.EASY:
			config.set_all_periods(1.5)
			config.army_commit_threshold = 8
			config.preserve_min_cost = -1
			config.retarget_switch_margin = 2.5
			config.scout_unit_budget = 1
			config.economy_reserve = 900
			config.build_concurrency = 1
		PlayerSlot.Difficulty.MEDIUM:
			config.set_all_periods(0.667)
			config.army_commit_threshold = 5
			config.preserve_min_cost = 250
			config.retarget_switch_margin = 1.6
			config.scout_unit_budget = 2
			config.economy_reserve = 600
			config.build_concurrency = 2
		PlayerSlot.Difficulty.HARD:
			config.set_all_periods(0.4)
			config.army_commit_threshold = 3
			config.preserve_min_cost = 0
			config.retarget_switch_margin = 1.3
			config.scout_unit_budget = 3
			config.economy_reserve = 450
			config.build_concurrency = 3
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
	return config


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
#endregion
