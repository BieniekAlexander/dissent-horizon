---
title: Bot parameter space
type: system-note
---

# Bot parameter space

*Design note for [Dissent Horizon](../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

**What an adversarial self-play search may move, what it may not, and why.**
[bot-architecture](bot-architecture.md) is what the bot IS; [bot-roadmap](bot-roadmap.md) is
what it should become. This note is the third question: **of everything the bot's play turns
on, which parts are numbers a run can search** — and, just as usefully, which parts are
orderings and branches that no value of any parameter can reach.

`BotDifficulty` is the whole surface. Nothing else is searchable, by design: a tier that
differed by a branch could not be held equal while another parameter moved, which is the
discipline that makes a search mean anything. What RUNS the search is
[selfplay-harness.md](selfplay-harness.md); this note is what it may put in the JSON.

## What changed, and what did not

Twelve fields were added to `BotDifficulty` (2026-09-04), each one a number that was
previously hardcoded in a manager. **Every default reproduces the play the bot had before the
field existed**, and the ramp ships FLAT — see §The tiers ship flat below.

| New field | Was | Now read by |
|---|---|---|
| `build_concurrency` | `BotEconomy` serialised builds unconditionally; the tier ramp landed 2026-09-12 | `BotEconomy.tick` |
| `production_structure_cap` | no cap existed | `BotEconomy._production_structure_to_build` |
| `utility_unit_cap` | `BotProduction.UTILITY_UNIT_CAP = 3` | `BotProduction._best_utility_unit_for` |
| `structure_demand_weight` | `Bot.STRUCTURE_IMPORTANCE = 0.4` | `Bot.enemy_demand_map` |
| `demand_coverage_falloff` | the literal `1.0 + coverage` divisor | `Bot.enemy_demand_map` |
| `attack_value_ratio` | `BotMilitary.ATTACK_RATIO = 1.3` | `BotMilitary._committing_to_attack` |
| `assumed_enemy_parity` | `BotMilitary.ASSUMED_ENEMY_PARITY = 0.85` | `BotMilitary._committing_to_attack` |
| `wave_abort_fraction` | `BotMilitary.WAVE_ABORT_FRACTION = 0.70` | `BotMilitary._should_abort_wave` |
| `squad_cap` | the wave and the reserve were the two squads, unconditionally | `BotMilitary._may_run` |
| `reinforce_fraction` | float | 0.0 – 1.0 | ordinal (higher = holds reinforcements longer) | 0 is the pre-2026-10-03 trickle, every new unit walking to the front alone; 1.0 waits until the reserve matches the wave it joins, which on a long wave never happens. Interacts with `WAVE_SPENT_FRACTION` (0.35, fixed): a wave spent below it ends before a slow reserve releases |
| `personality_spread` | float | 0.0 – 0.4 | ordinal (higher = less like its tier) | 0 is the tier exactly, which a controlled experiment MUST set; 0.4 of a range is a different tier as often as not. Not itself jittered |
| `decision_temperature` | float | 0.0 – 0.5 | ordinal (higher = less decisive) | 0 is the argmax every scored module used before; 0.5 takes an option half as good as the best often enough to read as careless. Not itself jittered; placement never reads it |
| `defend_threat_radius` | `DEFEND_THREAT_RADIUS = 10.0`, declared TWICE | `BotMilitary._decide_posture`, `BotSanction._engagement_zone` |
| `retarget_weight_effectiveness` | `BotTargeting.W_EFFECTIVENESS = 1.0` | `BotTargeting.set_signal_weights` |
| `retarget_weight_finishability` | `BotTargeting.W_FINISHABILITY = 1.0` | ” |
| `retarget_weight_proximity` | `BotTargeting.W_PROXIMITY = 0.5` | ” |

**One field was added later (2026-09-05) and it is the exception to everything below.**

| Later field | Was | Now read by |
|---|---|---|
| `income_structure_target` | the ladder's ORDERING — production capacity before income, unconditionally | `BotEconomy.effective_income_target` |

`income_structure_target` breaks two of this note's rules on purpose, and both breaches are
the point of it:

- **Its default does NOT reproduce the old play.** 1 means "one extractor before the first
  barracks", which is the whole question it was added to answer. 0 is the old opening, and it
  is the bottom of its range.
- **It is the first field that reaches a LADDER rather than a number.** §Ladders the search
  cannot reach item 1 said the opening ORDER was unreachable at every parameter setting; the
  income-versus-throughput rung of it now is. The part that is BLOCKED — trading a dominion
  structure against an extractor — is untouched, because that is the energy-versus-dominion
  question and this rung does not need it: an extractor and a barracks are both priced in
  energy.

**Three more were added later still (2026-09-11), and they are the first fields that reach a
DECISION the search could not previously express at all.**

| Later field | Was | Now read by |
|---|---|---|
| `place_frontage_bias` | the ring scan's first valid cell | `BotEconomy._bearing_for` |
| `place_shelter_bias` | ” | ” |
| `place_corridor_weight` | nothing — the scan had no opinion about clearance | `BotEconomy._scored_candidates` |

Where a building goes was not a number before them; it was a scan ORDER, and §Deliberately NOT
promoted said so explicitly of `SEARCH_MIN_RING` / `SEARCH_MAX_RING` — "a first-fit scan order,
not a placement policy — searching its bounds tunes an artefact". That entry is now spent: the
scan is a scored comparison ([bot-architecture](bot-architecture.md) §Where a building goes),
the ring bounds are the extent of the candidate disc rather than its ordering, and these three
are the policy.

**COMPACTNESS HAS NO WEIGHT FIELD**, and that is the same argument as THREAT below. The
placement score is only ever compared against other candidates for the SAME building, so
multiplying every weight by one factor changes no decision; one of the terms has to be the unit
of the scale, and the pull back toward the base centroid is it (`BotEconomy.COMPACTNESS_WEIGHT
= 1.0`). Searching it would spend a dimension of compute on a free scale, and the other three
already reach every ratio it could express.

It is also the first parameter whose effect is MODULATED at read time rather than read
directly: `BotEconomy.safety()` multiplies it, so a search moves what the bot wants when it is
safe rather than what it does. See [bot-architecture](bot-architecture.md) §The opening's
income rung reads the game.

Two of the original twelve deserve a note of their own:

- **`defend_threat_radius` was two copies of one number**, one in `BotMilitary` and one in
  `BotSanction`, each carrying a comment promising it mirrored the other. They are now one
  field pushed into both, so they cannot drift — which a hand-searched pair certainly would.
- **`structure_demand_weight` and `demand_coverage_falloff` live on `Bot`, not on a manager**,
  because `enemy_demand_map` is perception. `BotBrain._apply_config` writes them onto the bot
  exactly as it writes every other parameter onto a manager; nothing else assigns them.

**THREAT has no weight field.** The retarget score is only ever compared against the current
target's score times `retarget_switch_margin`, so multiplying every weight by one factor
changes no decision. One of the four has to be the ruler; searching all four would spend a
dimension of compute on a free scale.

## The tiers ship flat

Every new field has the same value in every tier — the value that reproduces today's play.
That is a position, not an omission. The seven original knobs are already a hand-made ramp
that [bot-roadmap](bot-roadmap.md) §Difficulty first explicitly says nothing should be
balanced against until a search has run; hand-ramping twelve more would multiply exactly the
guesswork the search exists to remove, and would make "opening a knob" indistinguishable from
"changing the game". A constant is monotone, so the ramp property `test_ScenarioPlayerSlots`
pins still holds, and **each field's doc comment records which direction is harder**, so a
ramp can be written the moment there is a measurement to write it from.

## The audit

Every hardcoded number in the bot modules, and what was done with it. "Direction" says which
way is more aggressive / greedier / faster.

### Promoted

| Where | Value | Controls | Direction | Note |
|---|---|---|---|---|
| `bot_economy.gd:63` | 1 job | construction jobs in flight | more = faster expansion, more fighters off the line | the rate limit on the whole opening |
| `bot_economy.gd:119` | (none) | how much production capacity to plan for | higher = greedier throughput | `-1` = uncapped is today |
| `bot_production.gd:39` | 3 | utility units maintained | higher = more map control + dominion loop, less army | the pool the opening scout and the builder come from. **A CEILING since 2026-09-05**, not the decision: `BotProduction._utility_demand_for` sizes the count to the live errands and this bounds it |
| `bot.gd:769` | 0.4 | an enemy structure's weight in production demand | higher = builds more anti-structure | the long game against the immediate one |
| `bot.gd:776` | 1.0 | how fast a covered threat stops being wanted | higher = diversifies sooner | 0 masses one counter forever |
| `bot_military.gd:49` | 1.3 | army-value multiple required to launch | lower = more aggressive | the real commit rule |
| `bot_military.gd:79` | 0.85 | assumed unseen enemy, as a fraction of us | lower = credulous, attacks phantom leads | the bot's whole model of the unseen |
| `bot_military.gd:95` | 0.70 | when a losing wave is called off | higher = cuts losses sooner | 0 = the pre-retreat bot |
| `bot_military.gd:37`, `bot_sanction.gd:37` | 10.0 | what counts as pressure on the base | higher = turtles / answers harass further out | was two copies |
| `bot_targeting.gd:47–49` | 1.0 / 1.0 / 0.5 | the retarget signal mix | per signal | threat is the scale |

### Deliberately NOT promoted

| Where | Value | Controls | Why it stays put |
|---|---|---|---|
| `bot_brain.gd:42` `PRESERVATION_HP_THRESHOLD` | 0.25 | when a unit reads as "at risk" | genuine, but it only fires behind the hopeless-matchup gate, and `preserve_min_cost` already searches the same behaviour by price |
| `BotBrain.PRESERVATION_PERIOD_SECONDS` | 1.0 s | preservation cadence | noticing a dying unit is not a handicap the tiers vary; a detail, not a preference |
| `bot_economy.gd` `SEARCH_MIN_RING` / `SEARCH_MAX_RING` | 2, 14 | how far from the base a spot may be | **the reason changed on 2026-09-11 and the verdict did not.** It was "a first-fit scan order, not a placement policy"; it is now the EXTENT of the candidate disc, and the policy moved into the three `place_*` weights. Bounds on a search region are still not a preference |
| `bot_economy.gd` `COMPACTNESS_WEIGHT` | 1.0 | the pull back toward the base centroid | the ruler the three `place_*` weights are measured against — see §What changed |
| `bot_economy.gd` `CORRIDOR_CAP_CELLS` | 4 | where more open ground stops counting | a saturation point, not a preference: without it the corridor term stops meaning "keep your lanes open" and starts meaning "go to the middle of the map" |
| `nav_placement.gd` `DETOUR_BUDGET` | 400 | when the connectivity check gives up and refuses | a compute bound with a conservative failure direction, not a behaviour |
| `bot.gd:43` `INFRASTRUCTURE_PROVIDER_MARGIN` | 40 | when to stand up a power plant | **first in the queue for round two.** It gates the whole ladder (nothing else is built while infrastructure is wanted); held back only because 12 knobs is the compute budget asked for |
| `bot.gd:225/240/247` | 30.0 | default threat radius | every decider passes `defend_threat_radius`; the default serves ad-hoc callers only |
| `bot.gd:294` `CLUSTER_LINK_DISTANCE` | 8.0 | what counts as one enemy force | changes what the bot SEES rather than what it wants; only sanction aiming and blast valuation consume clusters today |
| `bot.gd:1013/1015` | 4 / 180 s / 2 / 60 s | `game_phase()` | **dead code — nothing reads `game_phase()`**, exactly as nothing reads `relative_threat_level()`. Searching them would measure noise |
| `bot_military.gd:41` `OBJECTIVE_EPSILON` | 3.0 | re-task hysteresis | anti-thrash detail |
| `bot_military.gd:54` `STALEMATE_ESCALATION_PER_SEC` | 0.02 | how fast the commit bar relaxes | it and `attack_value_ratio` are the SLOPE and INTERCEPT of one line; searching both searches the same line twice at first order |
| `bot_military.gd:57` `MIN_ATTACK_RATIO` | 0.85 | floor under that line | same line, third parameter |
| `bot_military.gd:60` `MIN_ATTACK_ARMY_VALUE` | 300.0 | army floor before attacking | redundant with `army_commit_threshold`, which counts the same thing in bodies |
| `bot_military.gd:63` `ENEMY_VALUE_FLOOR` | 100.0 | divide-by-zero guard | implementation detail |
| `bot_military.gd:68` `ENEMY_ESTIMATE_TAU` | 30.0 | how long a sighting is believed | a property of BELIEF, which the roadmap wants modelled properly (a blackboard with history); tuning the decay now bakes in the crude version |
| `bot_military.gd:82` `WAVE_SPENT_FRACTION` | 0.35 | how deep a committed wave goes | second threshold on the same quantity as `wave_abort_fraction`; the momentum-gated one is the one that reads the game, this is a floor. Round two |
| `bot_military.gd:100` `REGROUP_SECONDS` | 20.0 | downtime after a retreat | exists to stop a one-think oscillation; round two, paired with the abort fraction |
| `bot_momentum.gd:32/41` | 8.0 s, 0.03 | the losing signal | a MEASUREMENT, not a preference — and it is ANDed with `wave_abort_fraction`, so searching both searches one boundary twice |
| `bot_scout.gd:26–30` `W_*` | 1 / 1 / .5 / .5 / 1.5 | which unit scouts | picks between spare units; small next to HOW MANY are away, which is already searched twice over (`scout_unit_budget`, the worth-it trade) |
| `bot_scout.gd:40` `INFORMATION_VALUE_ENERGY` | 400.0 | the price of knowing the map | **the strongest round-two candidate.** Held back because it prices a GAME quantity rather than a bot's preference: per-tier values would make the same information worth different amounts to different opponents, which is a claim about the world. The roadmap keeps such prices few, named and arguable |
| `bot_scout.gd:45` `ABSENCE_RISK` | 0.5 | share of a scout's price forfeited | the other side of that same comparison — only the ratio matters, so it is scale-locked to the line above |
| `bot_scout.gd:17/19` | 5, 60 s | grid resolution / staleness | resolution is compute; expiry is the DEFINITION of "blind", which the worth-it trade then prices |
| `BotKamikaze.EVAL_PERIOD_SECONDS` | 7.0 s | drone scan cadence | a throttle; seconds now, so no other period moves it |
| `bot_opportunist.gd:16` `PRISONER_VALUE` | 60.0 | what a prisoner is worth in energy | the energy-versus-dominion exchange is the roadmap's open modelling question; searching it tunes a proxy for an unmodelled trade |
| `bot_opportunist.gd:42/163/190/241` | 30.0 / 0.5 / 1.5 / 0.5 | garrison radius, denial bonus, full-truck bonus, bunker travel cost | small multipliers inside one gatherer, all scale-locked to `PRISONER_VALUE` |
| `contact_opportunity.gd:19` `TRAVEL_COST_PER_UNIT` | 2.0 | distance → energy exchange rate | its own comment invites a difficulty knob, but it only ever appears against authored guesses, so the whole opportunist scale wants settling together rather than one term of it searched |
| `bot_sanction.gd:42` `REINFORCE_PUSH` | 0.5 | where a reinforcement drop lands | aiming detail; plausible small knob, no plausible match outcome |
| `bot_targeting.gd:24` `DEFAULT_SCAN_RADIUS` | 8.0 | fallback for a unit with no aggro shape | implementation detail |
| `bot_targeting.gd:46` `W_THREAT` | 1.0 | the threat signal | the scale the other three are measured against — see above |

## The search space

Twenty-seven fields. **Ordinal** means the field has a direction ("more of this is a harder bot",
or at least "more of this is more X"); **categorical** means it does not, and the search must
treat it as a choice rather than as a dial.

| Field | Type | Range | Kind | Why those bounds |
|---|---|---|---|---|
| `combat_period_seconds` | float | 1/30 – 2.0 | ordinal | how often posture, retargeting, momentum and sanctions are revisited. 1/30 = every physics tick, the roadmap's own IMPOSSIBLE ceiling; 2 s = the PASSIVE value, past which whole engagements finish unseen |
| `strategy_period_seconds` | float | 1/30 – 2.0 | ordinal | economy, production and errands; same bounds |
| `scout_period_seconds` | float | 1/30 – 2.0 | ordinal | seeing and dispatching scouts; same bounds. The tiers ship all three equal (the old single think interval); searching them apart is new ground |
| `army_commit_threshold` | int | 1 – 12 | ordinal | 1 attacks with a single unit; 12 is past the army the bot fields before infrastructure binds. PASSIVE's 9999 is a SENTINEL for "never", not a search point |
| `preserve_min_cost` | int | −1, then 0 – 800 | ordinal (−1 = never, at the bottom) | 0 saves everything; 800 is above the priciest unit, i.e. equivalent to −1 again, so the interior is 0 to the dearest unit's cost |
| `retarget_switch_margin` | float | 1.0 – 3.0 | ordinal | 1.0 switches on any improvement (jittery, superhuman); 3.0 is the PASSIVE value, effectively "never switch" |
| `scout_unit_budget` | int | 0 – 4 | ordinal | 0 plays blind; above ~4 the `1/(n+1)` information divisor makes another scout worth less than any unit's absence, so higher values cannot bind. **Now one of the most consequential fields in the table**: the ATTACK objective is fog-limited, so a bot that has not found the opponent has no offensive at all. The tier ramp is 0/1/2/3/4 (it was a flat 1 below IMPOSSIBLE) |
| `economy_reserve` | int | 0 – 1500 | ordinal (lower = commits earlier) | 0 spends to zero; 1500 is several structures' worth, at which surplus never triggers |
| `may_attack` | bool | {true, false} | **categorical** | PASSIVE is a KIND of opponent, not a weaker one, and false makes half this table inert |
| `squad_cap` | int | 1 – 3, or -1 | ordinal (higher = more bodies manoeuvred at once) | 1 is one body: the trickle, whatever `reinforce_fraction` says; 2 is wave and reserve; 3 adds the guard, which answers a raid while the wave is out. **-1 is UNCAPPED** (`is_squad_uncapped`), and today means 3 — there are three squads to run |
| `build_concurrency` | int | 1 – 4, or -1 | ordinal | 1 is the serialised bot; **-1 is UNCAPPED** and must be tested with `is_build_uncapped`, never read as a count (`maxi(1, -1)` is 1). Above the number of builders it fields (itself bounded by `utility_unit_cap`) it does nothing |
| `production_structure_cap` | int | −1, then 1 – 8 | ordinal (−1 = uncapped, at the greedy end) | 1 = all-in on one building's output; 8 is past what a map's infrastructure supports |
| `utility_unit_cap` | int | 0 – 6 | ordinal | 0 removes the capture loop and the opening scout entirely; 6 is where the producer's spend crowds out the army. A CEILING on the demand model now, so above the demand it is inert — on Colonial content that demand is 2-4 per type, which is where the useful range ends |
| `income_structure_target` | int | 0 – 8 | ordinal (higher = greedier) | 0 is the pre-2026-09-05 opening — throughput first, income only through the fall-through. Above the sites a map offers it cannot bind (twelve on `skirmish.tscn`, contested), and `safety()` bends it down well before that: measured, a target of 4 stops claiming at ~2.5 because by then the bot has SEEN the opponent |
| `defence_structure_target` | int | 0 – 6 | ordinal (higher = turtles) | 0 is the bot before 2026-10-04, whose ladder had no rung for a static at all; 6 is a turret per approach on `skirmish.tscn`, past which the frontage spots run out and the rung falls through. Added 2026-10-04 with its rung (between income and throughput, only once a producer stands); measured two Watch Towers beat sixteen Recruits at twice their price (`sims/towers_vs_double_recruits`), which is why it does not ship at the old-play value |
| `tech_value_margin` | float | 1.0 – 3.0 | ordinal (higher = techs later) | the ratio by which the best unit behind a tech structure must outscore the best the bot can train, on composition value against the believed enemy. 1.0 techs the moment anything better exists; 3.0 is past any matchup the roster offers, so the bot never techs. The margin is the investment overhead (price, build time) represented without being priced. Added 2026-10-05 with the tech rung |
| `structure_demand_weight` | float | 0.0 – 1.0 | ordinal (higher = more anti-structure) | 0 never trains anything that razes a base, so it cannot close a game against a turtle; 1.0 is the top of the scale — a building mattering as much as a soldier |
| `demand_coverage_falloff` | float | 0.0 – 4.0 | ordinal (higher = diversifies sooner) | 0 masses the single best counter forever; at 4 one covering unit nearly zeroes a type's demand, which is maximal diversification |
| `attack_value_ratio` | float | 0.8 – 2.5 | ordinal (lower = aggressive) | below `MIN_ATTACK_RATIO` (0.85) the constant floor makes it inert, so 0.8 is the effective bottom; at 2.5 only the stalemate clock ever launches a wave |
| `assumed_enemy_parity` | float | 0.0 – 1.5 | ordinal (lower = credulous) | 0 trusts the seen slice completely; 1.5 assumes the enemy is half again our size and suppresses ratio-driven attacks entirely |
| `wave_abort_fraction` | float | 0.0 – 1.0 | ordinal (higher = retreats sooner) | 0 is the pre-retreat bot; 1.0 leaves on the first loss taken while bleeding. Below `WAVE_SPENT_FRACTION` (0.35) the rule is dead — the wave ends by being spent first |
| `defend_threat_radius` | float | 3.0 – 30.0 | ordinal (higher = turtles) | 3 ≈ a structure's own footprint, so only a unit standing on the base counts; 30 is `Bot`'s own default, which the module records as making the bot turtle forever on a small map |
| `retarget_weight_effectiveness` | float | 0.0 – 3.0 | ordinal, no "harder" direction | 0 ignores matchup; 3 outweighs threat and proximity combined |
| `retarget_weight_finishability` | float | 0.0 – 3.0 | ordinal, no "harder" direction | as above; high values chase wounded targets past healthy ones |
| `retarget_weight_proximity` | float | 0.0 – 3.0 | ordinal, no "harder" direction | 0 makes a unit walk past an adjacent enemy for a better trade inside the same leash; 3 makes it take whatever is nearest |
| `place_frontage_bias` | float | 0.0 – 1.5 | ordinal (higher = production at the front) | cost per cell toward the believed threat, against compactness = 1.0. 0 makes production directionless and the base concentric; above 1.0 the directional reward outruns the sprawl cost and every production building goes to the far edge of `SEARCH_MAX_RING`, so 1.5 is the top of the useful range rather than of the meaningful one |
| `place_shelter_bias` | float | 0.0 – 1.5 | ordinal (higher = support further back) | the same scale, AWAY from the threat, for infrastructure, the dominion structure and everything else the bot is not fighting out of. Same saturation at 1.0, same reason |
| `place_corridor_weight` | float | 0.0 – 3.0 | ordinal (higher = airier bases) | cost per cell of the footprint's minimum clearance, capped at `CORRIDOR_CAP_CELLS` = 4. 0 packs buildings against terrain and against each other; at 3 the capped reward (12) dominates the compactness term over the whole disc and the bot builds wherever the map is widest. The hard constraint already refuses a placement that SPLITS the map, so this is only the softer "don't pinch your own lanes" preference |

## Where holding-others-equal is a lie

The search's stated discipline is to move one parameter and hold the rest. These are the
places that discipline is violated by the code itself, and a run that ignores them will
attribute an effect to the wrong knob.

1. **A period is not only reaction time.** The scout's one claim per run, the economy's one
   build decision per run and `BotMomentum`'s sample density are counted per run of their
   job, so a faster `scout_period_seconds` also scouts up faster, a faster
   `strategy_period_seconds` also expands faster. This used to be one confound through a single
   `think_interval_ticks` (which also moved the kamikaze cadence); since 2026-09-26 it is three
   smaller ones, each confined to its own group.
2. **`economy_reserve` × `build_concurrency` × `production_structure_cap`** all gate the same
   spending: the reserve decides IF, concurrency decides HOW FAST, the cap decides HOW MUCH.
   Two of the three are dead in most of the third's range.
3. **`attack_value_ratio` × `assumed_enemy_parity` × `scout_unit_budget`.** The parity prior
   only binds while the enemy is unseen, so scouting DISABLES it; the aggression pair must be
   searched jointly with scouting or the prior will read as inert.
4. **`attack_value_ratio` × `army_commit_threshold`** are two commit gates in series (a value
   and a body count). Whichever is stricter binds, and the other is invisible. They were in
   PARALLEL until 2026-10-03 — the count alone returned ATTACK without launching a wave, so
   the looser gate bound and the retreat rule never applied to a count-triggered attack. See
   [squads-and-relations](squads-and-relations.md) §What started it.
5. **`wave_abort_fraction` × `WAVE_SPENT_FRACTION` (0.35, fixed) × `REGROUP_SECONDS` (20,
   fixed) × `BotMomentum.LOSING_LOSS_RATE` (0.03, fixed).** Retreat is an AND of two
   conditions with a floor under it and a cooldown after it, and only one of the four moves.
6. **`retarget_weight_*` × `retarget_switch_margin`.** The margin multiplies the CURRENT
   target's score, so a heavy proximity weight plus a high margin is not "prefers near
   targets" but "keeps whatever it first met".
7. **`structure_demand_weight` × `demand_coverage_falloff`** shape one number between them; at
   falloff 0 the structure weight becomes permanent rather than decaying.
8. **`utility_unit_cap` × `scout_unit_budget` × `build_concurrency`.** Utility units are the
   pool the opening scout and the builders are drawn from — `BotScout._scout_score` picks the
   unit nobody else wants, which early on IS the utility unit — so raising either consumer
   without raising the cap takes the unit from the other.
9. **`income_structure_target` is read through `BotEconomy.safety()`, so it interacts with
   everything that makes the bot feel unsafe** — `scout_unit_budget` above all, because safety
   falls only once the enemy has been SEEN. A blind bot reads as safe and spends its whole
   target; a scouting one bends its target down as soon as it finds an army. It couples to
   item 2 from the other side, too: those three gate throughput, and this one decides whether
   throughput is reached at all this think.
10. **`defend_threat_radius` now has THREE consumers**, not two — `BotMilitary._decide_posture`,
    `BotSanction._engagement_zone` and `BotEconomy.safety`. Widening it makes the bot turtle,
    aim sanctions further out AND stop expanding: one knob, three behaviours.
11. **`utility_unit_cap` × `build_concurrency` × `scout_unit_budget` is a real coupling now
    rather than a shared pool.** The last two are TERMS IN THE DEMAND that
    `utility_unit_cap` ceilings (`BotProduction._utility_demand_for`), so raising either
    raises how many utility units get BUILT rather than merely competing for them. Item 8's
    warning is unchanged and now has a mechanism.
12. **`defend_threat_radius` × the wave.** A committed wave OVERRIDES defence, so widening the
   radius does nothing at all while the bot is attacking and everything while it is massing.
13. **`may_attack = false` makes ten of the twenty inert.** PASSIVE should be scored as its
    own configuration, never interpolated toward.

## Ladders the search cannot reach

The honest half of this note. **These are decisions where the answer to "can the search find
the best X" is no — not because the values are wrong, but because the bot has no way to say
X at all.** Each is a fixed ordering or a missing action, and no parameter reaches it.

1. **The opening build ORDER — PARTLY REACHABLE since 2026-09-05.** `BotEconomy` is still a
   ladder: dominion structure, then infrastructure, then **income while the bot wants more
   than it owns**, then production if in surplus, then an extractor. **"Expand before a
   barracks" IS now sayable** — `income_structure_target` is that rung, and
   `BotEconomy.safety()` decides when it applies. What stays unreachable is the rest of the
   order (dominion and infrastructure are unconditionally first) and, BLOCKED rather than
   merely unbuilt, trading a dominion structure against an extractor: the roadmap's
   energy-versus-dominion question has to be settled before those two are comparable at all.
   The income rung did not need it, because an extractor and a barracks are both priced in
   energy.
2. **"How many of EACH production structure" is not expressible.** Which production building
   goes up is "one of a type I do not own yet, else the cheapest" — a fixed preference.
   `production_structure_cap` is a TOTAL. A plan like *three barracks to one factory* cannot
   be stated, and no value of any field produces it. This is the sharpest gap against the
   question that prompted the audit.
3. **The manager call order IS the arbitration.** Scout before Military because a claimed unit
   reads as non-idle; Opportunist before both. Priority between domains is a call order in
   `BotBrain.think`, not a weight — so "should this unit scout or fight" is answerable only
   for the one manager that was given a refusal (the Scout).
4. **The posture FSM.** DEFEND / ATTACK / MASS are branches; the search moves their
   thresholds but cannot make a bot that defends while ahead, that splits its army, or that
   leaves a garrison at home — **there is no own-side grouping**, so "half the army" is not a
   thing that can be named.
5. **Waves are structural.** Mass → commit → spent-or-abort is the shape. The roadmap wonders
   whether a steady stream plays better; that is not one parameter today, it is a rewrite of
   `BotMilitary.tick`.
6. **Training never trades quality for tempo.** Cost is not a tiebreaker: an unaffordable want
   makes a building WAIT. No parameter buys "spam something cheap now" — the only lever
   nearby is `demand_coverage_falloff`, which changes WHAT is wanted, not whether waiting for
   it is worth it.
7. **Where to build — NOW REACHABLE, and this item is the second ladder the search got.** It
   was "first fit on a ring expanding from the base centroid — a scan order, not a choice".
   It is now a scored comparison in the bot's own frame, and `place_frontage_bias`,
   `place_shelter_bias` and `place_corridor_weight` are what say where a building wants to be
   ([bot-architecture](bot-architecture.md) §Where a building goes). **A forward base is still
   not sayable** — the candidate disc is anchored on the base centroid, so "somewhere else
   entirely" has no expression — and neither is "spread out so one blast does not kill three",
   which wants a term over the bot's OWN structures that nothing computes.
8. **Sanction unlocks are greedy in grid order.** The bot buys whatever it can reach and
   afford; it cannot save dominion for a deeper sanction, so "which sanction route" is
   unsearchable.
9. **Whole verbs are missing.** No repair, no unit ability, no `Defend` / `Patrol` / rally
   point, nothing aerial (land, dock, rearm). Any strategy that needs one of those is outside
   the space at every parameter setting — see [bot-architecture](bot-architecture.md) §The
   action space is a third of the game.

Items 1, 2 and 4 are the ones a search will feel first, because they are the three the user's
own questions land on.

## Proving the defaults

The rule for adding a knob here: **the suite must be identical by test NAME, not by count**
(CLAUDE.md §A skipped test file is invisible). The promotion above was run that way — 2004
tests before, and after, every one of those 2004 still present and with the same single
pre-existing failure (`test_ControlBinding.gd::test_grid_collisions_are_all_acknowledged`)
and the same pending (`test_BotTestScenarios.gd::test_kamikaze_cluster_scenario`, flaky until
the sim RNG is seeded). The eight extra tests in the "after" run were a concurrently-added
`test_SeededRandomness.gd`, not a consequence of this change.

`tools/simulation/run_scenarios.gd` is the part that matters: it drives whole scenarios, so a
default that failed to reproduce the old constant would show up as a scenario that no longer
reaches its assertion.

**A silent knob is the failure mode a name comparison cannot catch**, and one of the twelve
was exposed to it: `BotTargeting.set_signal_weights` resolves its three signals by name, and
because every default equals the constant it replaced, a match that stopped resolving would
leave the mix looking right and the parameter dead. It therefore warns when it applies fewer
than three, and the run confirms it applies all three on every call. Any future knob wired
through a lookup rather than an assignment wants the same treatment.

## Feeding it from the harness

The self-play harness injects values by reflecting over `BotDifficulty`'s properties, so:

- **Every field is a plain typed `var`** — `int`, `float` or `bool`, nothing else. No arrays,
  dictionaries, enums or resources, which is what keeps a configuration a flat JSON object.
  They are not `@export`s: `BotDifficulty` is a `RefCounted` rather than a `Resource` (there
  is no per-scenario authoring story yet), and `get_property_list()` reports plain script
  variables regardless.
- **JSON has one number type**, so an int field arrives as a float. Assign through
  `Object.set()` (or `int()` first) rather than a statically-typed path, which refuses the
  narrowing. The ints are `army_commit_threshold`,
  `preserve_min_cost`, `scout_unit_budget`, `economy_reserve`, `build_concurrency`,
  `production_structure_cap`, `utility_unit_cap` and `income_structure_target`.
- **Two fields carry sentinels rather than being continuous**: `preserve_min_cost = -1`
  ("never") and `production_structure_cap = -1` ("no cap"). A sampler that interpolates
  across them will produce nonsense between −1 and 0; treat each as a discrete point at the
  end of its range.
- **`may_attack` is the one bool and is not a dial.** It defines PASSIVE, so it belongs in a
  separate configuration rather than in the same sweep.
