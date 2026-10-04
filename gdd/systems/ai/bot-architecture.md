---
title: Bot architecture
type: system-note
---

# Bot architecture

*Design note for [Dissent Horizon](../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

**What is built today.** The roadmap — what it should become — is
[bot-roadmap.md](bot-roadmap.md).

## Three layers, and the rule that separates them

```
PERCEPTION   Bot (bot.gd)            a Commander subclass; ~60 read-only "senses"
   ↓         nothing is mutated here
DECISION     BotBrain + 9 managers   jobs on their own periods, paced by BotScheduler
   ↓         nothing is issued here
ACTION       BotActuator             the ONLY place the bot mutates game state
```

**The actuator rule is the load-bearing one.** Every command the bot issues goes through
`BotActuator`, so the decision code stays pure and testable and there is a single audited
surface for "the bot did a thing". A manager that issued a command directly would be
untestable and invisible, and the discipline is what lets every module below be driven from
a headless test.

`Scenario._attach_brain` gives one `BotBrain` to each non-human, non-neutral commander.

A bot uses a unit it did not train — one the debug spawner hands it, say — because it reads
its units from the tree and an unclaimed unit is the army's.

Every slot's commander is a `Bot`, the human's with its brain off, so debug mode can hand a
slot between the player and its bot: `Bot.is_ai_controlled()`, not `is Bot`, says whether the
bot decides. See [debug-mode](../ux/ui/debug-mode.md) §A bot for every slot.

## The think pass

Each manager runs as a job on its own period — combat, strategy or scouting, each a
`BotDifficulty` field in seconds — paced by one `BotScheduler` per session against a shared
work-unit budget. Order is no longer arbitration: who owns a unit is a `BotClaims` entry. See
[think-scheduling](think-scheduling.md). `BotBrain.think()` still runs every job once, for
tests and probes. The managers:

| # | Manager | Decides |
|---|---|---|
| 1 | `BotEconomy` | what the one free builder builds next |
| 2 | `BotProduction` | what each idle production building trains |
| 3 | `BotOpportunist` | utility-scored one-off actions (liberation, capture/deposit) |
| 4 | `BotScout` | which unit goes to the stalest point on the scout grid |
| 5 | `BotMilitary` | the army's posture (DEFEND / ATTACK / MASS) and its objective |
| 6 | `BotTargeting` | per-unit retarget, weighted signals with a switch margin |
| 7 | `BotKamikaze` | AOE-suicide runs worth their airframe (slow ~7s cadence) |
| 8 | `BotSanction` | unlock and deploy commander abilities |
| 0 | `BotMomentum` | samples where the bot STANDS — army-value trend — before anyone reads it |
| — | `_tick_preservation` | pull a hurt unit out, once a second |

**A manager keeps a unit by claiming it** (`BotClaims`): scouting < combat < errands <
exclusive, and the army is whatever nobody has claimed. This replaced *priority by call order*
(the Opportunist and the Scout running before the Military's idle sweep) when each manager
got its own period on 2026-09-26.

The Scout also DECLINES a claim when scouting is not worth the unit's absence, so the Military
gets the unit by the Scout's own reckoning rather than by losing a race. That refusal, in the
currency below, is still the model for the other managers.

## What each module actually does

- **`BotEconomy`** — a priority ladder, one build per think, one builder: a dominion structure
  if we own none → an infrastructure provider if capacity is tight → **an extractor while the
  bot wants more income than it owns and nothing is pressing** → a production building if
  energy is in surplus (another dominion source first, for a route that pays by site) — the
  one whose best unit the demand map wants most, cost as the tiebreak, since cheapest-first
  meant a second barracks every time and never a second war factory → an
  extractor on a free site. WHICH structures is derived from the
  buildable set classified by component (`EnergyExtractor`, `Production`) and, for dominion,
  by the faction's route (see §Dominion routes) — never hardcoded, so a newly-added building is picked up automatically. **One
  rung is no longer fixed** — see §The opening's income rung reads the game — and one hazard
  the ladder always carried is now guarded: see §A build that never finishes.
- **`BotProduction`** — the most interesting module and the model for the rest. No per-unit
  rules and no cheap-unit bias: each idle building trains the producible unit with the
  highest `unit_composition_value` — effectiveness against the believed enemy × per-type
  demand, where demand falls as the army already covers a threat. Cost is NOT a tiebreaker;
  an unaffordable want makes the building WAIT rather than train something weaker. **The
  utility units are on the same footing now**: how many builders and carriers to keep is one
  per live ERRAND (`_utility_demand_for`) rather than the flat count-per-type it used to be,
  and `utility_unit_cap` is the ceiling on that answer rather than the answer.
- **`BotMilitary`** — a three-state posture FSM over one objective position, re-tasking the
  whole army only when the posture or objective changes. **The ATTACK objective is a BELIEF**
  (see §The attack objective is a belief), and the army it commands is everything with combat
  utility — armed *or* able to crush, which is what stopped an unarmed Stock Truck being
  filtered out of both the re-task and the idle sweep and left standing for the match. **Its commit rule is the one real
  strategic COMPARISON in the bot**, and richer than "a threshold": own army value against a
  decayed-peak estimate of the believed enemy, under a humility prior (never assume the unseen
  enemy is weaker than 0.85× our own), with the bar relaxing the longer the bot holds without
  fighting so two even bots cannot deadlock, floored so a losing one does not throw its army
  away. **It retreats**: a wave is called off once the army has lost 30% of its launch value
  AND `BotMomentum` says it is still bleeding — both halves, because losses already taken are
  not a reason to leave and a bot that pulls back on damage dribbles its army in. A
  called-off wave regroups at home for 20 seconds.
- **`BotScout`** — a grid of last-seen timestamps; scouts are dispatched on the ERRAND with
  the best expected return and HELD across another manager's re-task (see §Scouting). Three
  comparisons, not three rules: WHICH unit scouts is a score over facts (speed, vision,
  replacement cost, how many of its other jobs are live); WHETHER another should scout at all
  is an energy-equivalent trade-off — information value scaled by how blind the bot is and
  divided by the scouts already out, against the unit's price times the share of it absence
  forfeits; and WHERE it goes is expected sightings per second, weighted by how likely the
  enemy is to be there. `scout_unit_budget` is a ceiling on the outcome, not the decision —
  and it is a real per-difficulty ramp (0/1/2/3/4) rather than the flat 1 it shipped as,
  because a fog-limited attack objective makes "how many units will this bot spend looking"
  one of the strongest handicaps in the table.
- **`BotMomentum`** — whether the bot is winning: the army-value trend over an 8-second
  window, read as a loss rate. Blind to the enemy's losses, deliberately (belief ratchets up
  as an attack reveals more, so any enemy-side trend reads a good push as a rout).
- **`BotOpportunist`** — the one place decisions are COMPARED rather than sequenced: domain
  gatherers return scored `BotOpportunity`s in energy-equivalent value, the best are executed,
  capped at one action per actor per tick.
- **`BotTargeting`** — a weighted-signal scorer with a switch margin (commitment) and think-
  cadence latency (reaction time). Four signals registered: threat, matchup effectiveness,
  finishability, proximity.
- **`BotSanction`** — unlocks greedily whatever its `SanctionGrid` gates allow and it can
  afford, then deploys by policy: defend the base, else strike the army, else hold. It
  decides WHICH sanction, WHICH caster and WHERE; whether the cast is permitted at all is
  `UseSanction`'s to answer, because the bot issues the same command the player does.
- **`BotKamikaze`** — detects an AOE-suicide unit from its projectile rather than by name,
  and spends one only when the blast's value beats the drone's own cost. Its HOLD is enforced
  rather than advisory: a drone with no worthwhile blast has its own target acquisition
  suppressed (`Commandable.is_holding_fire`) and any aggro-acquired engagement dropped, so
  proximity cannot override the cost-effectiveness decision the module exists to make.

## Scouting

*Rewritten 2026-09-11 after a Colonial-vs-Colonial MEDIUM match in which the Stock Truck —
the piece the suitability score was built to pick — never scouted at all, and neither bot
laid eyes on the other's base for most of the game. Both symptoms had causes, and none of
them was the score.*

Three faults compounded, in the order a think pass meets them.

### 1. The claim was surrendered to a standing rally

*History: this predates BotClaims; a scout is now simply skipped by the military's re-task.*

`BotBrain.think` ran `BotScout` **before** `BotMilitary` on purpose: a unit given a move
order here is non-idle when the military's idle sweep runs, and so is protected from an
immediate `AttackMove`. That protection covers the idle sweep and nothing else.
`BotMilitary.tick` re-tasks the **whole army** whenever the posture or the objective moves,
and the objective in MASS posture is the base centroid, which drifts every time a building
goes up. Every unit with combat utility is swept into that — including the Stock Truck, which
carries no weapon but can crush, and has done since `unit_has_combat_utility` was widened.

`BotScout` then dropped any scout whose command was no longer its own. Measured, seed
20260910, sampled every simulated second:

| Think | What happened to the truck |
|---|---|
| 1 | claimed by `BotScout` (score 1.00, the highest), given a Move |
| 1 | overwritten with `AttackMove` to the base centroid by `BotMilitary` |
| 2 | dropped from `_scouts` as "re-tasked"; a Servant at half its speed becomes the scout |
| 3 … end | never held again — 0% of samples over four 300-second matches |

That is the user's report exactly: *"they idle and move around in a very small area of the
map"*. The truck spent the match shuffling around a drifting rally point.

**The fix is that a claim is now HELD.** A scout is given up for exactly three reasons
(`BotScout._still_scouting`): it is gone (freed, or taken into a garrison), it has been given
a **real errand** (`_yields_to_errand` — Attack, Build, Assemble, Repair, Occupy, Capture,
Land, Interact), or its absence has **stopped paying for itself** at the rank it occupies.
An `AttackMove` is none of those: it is a standing rally issued to everybody, not a decision
about this unit, so the module answers it by re-issuing the waypoint on the next think.

The third reason is what stops this becoming a unit the army can never have back — once the
map is known, `stale_fraction` collapses, the trade-off fails, and the scouts release
themselves. It is also why the retention test takes a RANK: asking the claim-time question
("is another scout worth it") of a scout already out would price the first one as if it were
a second, halve its value and release it for nothing.

### 2. The picker and the price test did not compose

`_pick_best_scout` returned the single best-SCORING candidate and the caller then priced it.
If that one candidate failed the price test, the think ended having claimed nothing — even
with a cheaper unit standing next to it that would have passed.

The failure is systematic rather than occasional, because **the two tests pull in opposite
directions on the same fact**: the scorer rewards capability, the price test punishes
replacement cost, so the top-scoring candidate is the one most likely to be unaffordable.
Measured: a MEDIUM bot (`scout_unit_budget` = 2) sat at **one** scout for entire matches. The
truck won the score every think and was rejected every think — 400 × `ABSENCE_RISK` 0.5 = 200
against a second scout's 400 × 0.93 ÷ 2 = 186 — and the Servant that would have passed was
never considered.

`_pick_scout` now walks the candidates in score order and returns the first the bot can
justify. Mean scouts out over four matches: **1.30 → 1.79**.

### 3. Nearest-first is a spiral

The destination used to be the nearest expired frontier point. That is the right answer to
"cover the most ground per second" and the wrong answer to "find somebody": the nearest
unseen cell is always the one just outside what you have already seen, so the scout shaves
its own frontier one cell at a time and fills in its own corner of the map before it starts
on the far side. Measured, seed 20260910: the closest the seen set got to the opposing start
point was **97.5 world units at t = 10 s and still 97.5 at t = 120 s** — it did not move at
all. Across four matches the enemy's base was found in **2 of 8 bot-matches within 300
seconds**, both at 265 s.

A destination is now scored as **expected sightings × enemy likelihood ÷ travel seconds**:

- **Expected sightings** (`_expected_sightings`) counts the candidate points inside the
  scout's own vision window at the destination, **plus the ones it sweeps up on the way**.
  Counting the journey is what makes a long errand cost-competitive: walking twice as far
  takes twice as long and reveals roughly twice as much, so the rate is nearly flat in
  distance and the nearest point loses its automatic win. The corridor term is a deliberate
  ESTIMATE — the path is sampled at grid spacing (capped at `MAX_PATH_SAMPLES`) and the
  fraction of dark samples scales a corridor of that length — because the exact form is a
  thousand-by-thousand sweep on every dispatch and this runs inside the think pass.
- **Enemy likelihood** (`_enemy_prior`) rises with distance from HOME, floored at
  `HOME_PRIOR_FLOOR` so the bot does not write off its own approaches. This is the term that
  decides whether a scout ever crosses the map, and the honest framing is that **with a
  uniform prior over unseen cells, nearest-first is CORRECT** — every cell is equally likely
  and the nearest is cheapest. Crossing the map requires believing the opponent is somewhere
  in particular, and the belief used is the weakest one that is true of any map worth
  playing, derived entirely from what this bot can see: *the opponent is not standing next to
  my own base, because I can see my own base.*
- **Travel seconds** comes from the scout's own `Movement.speed`, so a fast unit is allowed
  to reach further for the same return.

Frontier-first is unchanged and still load-bearing: a never-seen point is preferred to a
merely-stale one however near the stale one is, because the bot's own base refreshes a disc
around home forever and one pass over "expired" re-walks it forever
([bot-engagement-fixes](bot-engagement-fixes.md)). Both passes still require the point to be
EXPIRED, which is what keeps an unreachable cell from trapping a scout.

### Where this sits relative to the fog

**The prior is about distance from the bot's own base, not about where the enemy starts.**
The scout walks toward open map and learns nothing until it arrives and looks; the ATTACK
objective is still a belief written by a real sighting (§The attack objective is a belief),
and a bot that has not found anybody still has no offensive.

**Decided: the bot does not read the map's authored start points.** It was asked whether
`BotScout` may treat `Skirmish.START_POINT_GROUP` as prior knowledge — exact rather than
inferred, at the cost of the bot knowing a fact about the SCENARIO rather than about game
state, and of nothing to fall back on where the prior is wrong (asymmetric maps, 3+ players, a
bot pushed off its start). Kept as shipped: the 95–110 s search above already delivers the
behaviour asked for, and it is the only option that needs no argument about what the bot is
allowed to know. `scout_knows_start_points` as a difficulty parameter is the next move if that
search is ever judged too slow — it turns the question into a tier rather than a rule.

### Measured, before and after

Four seeds, Colonial mirror on `skirmish.tscn`, both slots MEDIUM, ~300 simulated seconds,
eight bot-matches per column.

| | before | after |
|---|---|---|
| Coverage at 60 s | 0.053 – 0.102 | **0.238 – 0.260** |
| Coverage at 150 s | 0.128 – 0.207 | **0.392 – 0.458** |
| Coverage at ~290 s | 0.269 – 0.466 | **0.473 – 0.550** |
| Enemy base located within 300 s | 2 of 8 | **8 of 8** |
| …when | 265 s | **95 – 110 s** |
| Closest approach to the opposing start point | 21.9 mean | **2.5 mean** |
| Samples with the Stock Truck scouting | 0% | **45%** |
| Mean scouts out (budget 2) | 1.30 | **1.79** |
| Throughput (ticks / wall second) | 148 | 149 |

The throughput row is the cost of the new selector, and it is nil: the map transform is
inverted once at grid-build time rather than per sampled point, which paid for the extra
work.


## The decision surface

**Every decision a commander must make, and where this bot makes it.** The list is
organised by WHAT IS BEING SPENT, which is what makes it checkable for completeness: a
commander allocates energy, dominion, ability charges and unit-time, and nothing else.

| Question | Decided in | How it decides |
|---|---|---|
| **Energy** — build what | `BotEconomy` | ladder, with the INCOME rung modulated by a safety signal |
| — how much income before throughput | `BotEconomy.effective_income_target` | **searchable target × how safe the bot is** |
| — build **where** | `BotEconomy._find_build_spot` | FIRST FIT on a ring expanding from the base centroid, rejecting anything that would sever the map. A scan order, not a choice |
| — train what | `BotProduction` | **derived comparison** — the model for the rest |
| — how many UTILITY units | `BotProduction._utility_demand_for` | **one per live errand**, capped |
| — spend or bank | `BotDifficulty.economy_reserve` | threshold |
| — repair what | *nowhere* | **not a decision the bot can make** |
| **Dominion** — unlock which sanction | `BotSanction._unlock_affordable` | greedy: buys everything reachable and affordable, in grid order |
| **Charges** — use a sanction now | `BotSanction` | policy ladder: defend, else strike, else hold — issued as `UseSanction`, so every rule about whether the cast is ALLOWED belongs to the command |
| — aim it how | `Sanction.targeting` + `min_targets` | **authored per ability** — the right shape |
| — use a UNIT's ability | *nowhere* | **not a decision the bot can make** |
| **Unit-time** — which unit scouts, and whether | `BotScout` | **scored, in energy-equivalent** |
| — what the army does | `BotMilitary` | posture FSM, with a real comparison on the commit |
| — which enemy to go for | `Bot.nearest_enemy_structure_to_base` | fixed rule |
| — group, merge, split the army | *nowhere* | **no own-side grouping exists** |
| — hold a region (deliberate idleness) | *nowhere* | `Defend` is never issued |
| — retreat a unit | `BotBrain._tick_preservation` | hopeless-matchup test |
| — retreat an army | `BotMilitary` | losses **and** momentum |
| — per-unit retarget | `BotTargeting` | scored, four signals |
| — one-off errands (capture, deposit, liberate) | `BotOpportunist` | **scored, in energy-equivalent** |
| — aircraft: land, dock, rearm | *nowhere* | the bot has no concept of any of it |

### The action space is a third of the game

`BotActuator` exposes **ten** verbs — `move`, `attack_move`, `attack`, `build`, `train`,
`interact`, `garrison_into`, `evacuate`, `rally`, `use_sanction` — against the command
classes. The bot therefore cannot `Repair`, `Defend`, `Patrol`, `Stop`, `Embark`, `Land`,
`Rearm`, `Bombard`, `FocusFire`, `Spot`, `AirDropRun`, or use an `Ability`.

**The actuator's verb list is the honest statement of what the bot can do**, and
`tests/test_BotCommandCoverage.gd` is what stops it drifting from the controller's. Every
command class is classified there into one of four buckets — ISSUED, COVERED_OTHERWISE,
NOT_THE_BOTS, MISSING — and the test enforces it **in both directions**: a new command nobody
classified fails the run, an ISSUED claim the bot does not actually make fails the run, and a
gap the bot has since filled fails the run rather than sitting in the table as fiction.

Coverage is DETECTED (by finding the construction in the bot's own source) rather than
declared, because a table that took the author's word for it would reproduce the silent
failure one level up. **The gap list is the deliverable, not an embarrassment**: it is fine
for the bot not to use a command, and the point is that each omission is a stated position
rather than an oversight.

**`BotSanction` used to be the exception to the actuator rule and no longer is** (2026-09-04).
It fired the sanction's event through the `ScenarioTriggerManager` and spent the charge
itself — a SECOND IMPLEMENTATION of the player's action, which skipped every gate in
`UseSanction.meets_precondition` (unlocked, a real caster, finished, powered, charged, target
spotted) and which nothing compared against the first. It now issues `UseSanction` through
`BotActuator.use_sanction`, the player's own route, and holds no reference to the event host
at all. **The lesson generalises: a bot that reproduces an action instead of ordering it will
drift from the player's version silently**, because no test is looking at both.

### The bot never queues commands, deliberately

Every actuator call is `update_commands(cmd)` — a replacement, never an append. A bot that
built command queues would have to decide how long a queue to build, and the answer to that
is not obviously finite. **Standing behaviour is the queue-free alternative**: a rally point,
a `Defend` post or a `Patrol` route is one order that keeps a unit busy indefinitely, and
costs one decision rather than a plan. The bot issues none of the three today, which is why
its only answer to "this unit is idle" is to sweep it into the attack.

## What the bot models about the enemy

`Bot.enemy_demand_map()` over the commander's blackboard belief, plus
`unit_effectiveness_vs` off the damage matchup table — and off the CRUSH rule since
2026-10-04: a vehicle heavy enough to run a target over counts at least
`Bot.CRUSH_EFFECTIVENESS` against it however poorly its gun does. **Measured, and the
expectation was wrong:** the watched claim was that the Matilda, an anti-mech crusher, would
trump infantry by driving over it. `sims/matildas_vs_recruits` says two Matildas LOSE to
twelve Recruits at cost parity in three seeds of three, while `sims/sloops_vs_recruits` has
two Sloops beat ten in three of three — under attack-move a vehicle stops to shoot rather
than driving through, so a crush is incidental. The constant therefore sits BELOW parity:
the bot's preference for the Sloop against infantry is the right reading of the game as it
plays, and the Matilda's value is against mechs, where its gun is. Raise the constant when
the bot learns to drive vehicles through infantry on purpose. So the bot reasons about COMPOSITION
from real stats — the user's "the bot should derive combat effectiveness from the stats in
the game" is already true, and it is why adding a unit needs no bot change.

It does NOT model: the enemy's economy, its tech, its production capacity, where its army
will be next, or what it is likely to do. Nor does it model **change** — the blackboard says
what exists and where, never what is different from a minute ago — or **whether the bot is
winning**. `relative_threat_level()` computes an instantaneous strength ratio and nothing
reads it. See [three-layer-comparison](three-layer-comparison.md) §The snowball effect.

**Clustering is the primitive between one unit and the whole army**, and perception answers
two different questions with it: `enemy_clusters()` GROUPS visible enemy units into forces
(centroid, strength, energy value, heading), while `best_covered_point()` answers where a
radius-R effect should land. A group's centroid does not answer the coverage question — a
chain of units is one group whose centre may reach none of them — which is why both exist.
`BotSanction`'s aiming and `BotKamikaze`'s blast valuation are the same scan asked two
questions; `Bot.entity_strength` is likewise the single definition of "how strong is this",
shared by `estimate_army_strength`, `relative_threat_level` and a cluster's strength.

## The attack objective is a belief

**Where the army marches is fog-limited, and that is a decision rather than an omission.**
`BotMilitary._objective_for(ATTACK)` reads `Bot.nearest_believed_enemy_structure_position()`,
falling back to `nearest_believed_enemy_unit_position()`; both answer off the commander's
blackboard. An opponent this bot has never SEEN yields no objective at all, `tick()` demotes
the posture to MASS, and the bot builds up at home until it finds somebody. **Scouting is the
precondition for aggression.**

What it replaced: `nearest_enemy_structure_to_base()` and `get_enemy_units()` read the live
scene, so the bot knew where the opponent had built from tick 0 and where every enemy unit
stood right now, without ever having looked. That was measurable — `has_attack_objective` true
from tick ~300 with `believed_enemy_army_value` still 0 — and it made
`BotScout.INFORMATION_VALUE_ENERGY` a price for something the bot was already getting free.
`nearest_enemy_structure_to_base()` survives as a query about what EXISTS (the hostile-target
audit uses it that way); nothing marches on it.

Both queries answer with a POSITION rather than a `Commandable`, and they have to: a belief
outlives the thing it remembers — the blackboard drops a structure only when the commander
regains vision of its spot and finds it gone — so "the last place I saw their base" is still
somewhere worth marching on after the building has been destroyed. The walk is
self-correcting: arriving grants vision, the revisit drops the belief, and the next think
picks something else or falls back to MASS.

**It costs engagement, and the cost is measured rather than assumed.** In a controlled
six-seed A/B — one tree, one change — the verdict did not move (0/6 decisive either way at a
ten-minute cap) but both sides' army value more than DOUBLED and their standing structures
nearly did, because with the objective fog-limited far less of either army dies. The bot that
has not found the opponent's base marches on the last place it saw a scout instead. Numbers,
mechanism and the open TODO: [bot-engagement-fixes](bot-engagement-fixes.md) §Fog-limiting the
attack objective.

**Under HEGEMONY the objective is the enemy's command centre** (`Scenario.win_condition`): the
nearest believed, actionable centre wins over any nearer building, and the bot's own centre is
the first thing the army turns to defend, judged threatened at twice `defend_threat_radius`
(`BotMilitary.COMMAND_CENTRE_THREAT_MULTIPLIER`). Where changes; WHEN does not — the commit
gates still decide, which is what separates a snipe from a premature commitment
([objectives-and-completion](../scenario-scripting/objectives-and-completion.md) §Win
conditions). Tests: `tests/test_BotHostileTargets.gd`, `tests/test_Elimination.gd`.

### …and it has to be something the army can ACT on

**Fog-limiting was never the only requirement on an objective.** A belief is only worth
marching on if arriving can lead to something happening, and until 2026-09-11 nothing asked
whether it could. `BotMilitary._objective_for(ATTACK)` now filters the belief set through two
questions before taking the nearest, and a rejected belief is skipped rather than fatal — the
army marches on the base behind the thing it cannot touch:

- **Can anything in the army damage it?** `Bot.any_unit_can_damage` over
  `_combat_units`. The unit-level form is `Bot.unit_can_damage` — a weapon that can lock onto
  the target (`Loadout.weapon_for_target`, its own or a bunker occupant's), or a size class
  heavy enough to drive over it (`Movement.can_crush`). The crush half matters: the army
  admits an unarmed Stock Truck *because* running infantry over is how the Colonials take
  prisoners, so a weapon-only test would judge an army of them unable to hurt anything.
- **Has the walk already disproved it?** `Bot.belief_is_disproved` — the bot has vision of the
  remembered spot and the remembered UNIT is no longer on it. Structures always answer false:
  `CommanderBlackboard.update` already drops a structure belief on a revisit that finds it
  gone. Unit beliefs had no such rule, only a three-minute timer, so the "walk is
  self-correcting" claim above held for half the beliefs the army marches on.

**"No targeting mode" and "a multiplier of zero" are different facts, and only the first was
available at the objective.** `Bot.unit_effectiveness_vs` answers 0 both for "this weapon
cannot lock onto that at all" and for "the weapon does no damage", so counter-effectiveness —
which decides what to BUILD and which target to PREFER — cannot decide what is a legal thing
to commit to. `weapon_for_target` is the question that can: a weapon may fire iff its
`target_mask` intersects the target's TARGETABLE_GROUND / TARGETABLE_AIR layers. Aggro
(`Commandable.get_aggro_near_position`) and `BotTargeting._retarget` had always asked it; the
places that did not were the two that decide where an army GOES and what a drone COMMITS to.

The same question is now asked at two more layers, because an objective is not the only way a
bot unit acquires something it cannot hurt:

- **`BotActuator.attack` refuses to issue an impossible Attack**, by asking
  `Attack.meets_precondition` exactly as `use_sanction` asks `UseSanction`'s. Nothing
  downstream would: `Commandable.update_commands` does not consult preconditions (that is the
  player UI's job), and a persistent Attack with no usable weapon returns `self` from
  `get_updated_state` for ever — the unit stands beside its target holding an order it can
  neither finish nor abandon.
- **`Bot.kamikaze_best_target` only anchors a blast on a body the drone can strike**
  (`unit_can_shoot` — a blast is delivered by a weapon, and being heavy enough to drive over
  something is not a way of getting a bomb onto it). With no such body the drone is HELD,
  which is `BotKamikaze`'s designed answer, instead of flying at an air target and waiting.

Measured, mechanism and the residual: [bot-engagement-fixes](bot-engagement-fixes.md) §The
objective nobody could act on. Cover: `tests/test_BotUntargetableCommitment.gd`.

## The opening's income rung reads the game

**"Build an extractor before a barracks" is a searchable NUMBER bent by a signal, not a build
order.** `BotDifficulty.income_structure_target` (default 1) is how many income structures the
bot wants standing before it adds throughput; `BotEconomy.effective_income_target()` is that
number times `BotEconomy.safety()`, rounded. Greed when safe, capacity when threatened —
safety can only ever bend the target DOWN, so a bot is never greedier than its parameter says.

`safety()` is built from signals the bot already had, and from nothing new:

- **Is anything of mine under attack** (`Bot.is_base_under_threat`, at the same
  `defend_threat_radius` the military and the sanctions read). Not a matter of degree: an
  enemy in the base returns 0.
- **How outgunned do I believe I am** — `believed_enemy_army_value` against
  `army_resource_value`. This is `relative_threat_level()`'s question asked FOG-LIMITED, and
  deliberately so: that sense reads the live scene, and handing the economy perfect knowledge
  of an army the bot has never seen is exactly the omniscience §The attack objective is a
  belief removed. **Having seen nothing therefore reads as SAFE**, and being wrong about that
  is what makes scouting pay — the same argument, one module over. Note the intended asymmetry
  with `assumed_enemy_parity`: that prior exists to stop the bot ATTACKING on a phantom lead,
  and applying it here would instead stop it ever expanding on a map it has not scouted.
- **Am I bleeding right now** — `BotMomentum.loss_rate`, normalised by its own losing
  threshold. Being smaller than the enemy and being killed by them are different situations
  and only the second is urgent.

**What it bought, six seeds, MEDIUM mirror, 360 simulated seconds, twelve slot-trajectories
per arm** (raw JSONL: `tools/selfplay/results/opening-ab-2026-09-05-*.jsonl`, read with
`opening_ab_analyse.py`; the `before` arm is the same tree with `income_structure_target = 0`
and the utility demand model pinned to the old flat cap). First extractor finished at **120 s → 60 s** (the site is claimed at 40 s rather
than 100 s), and the army it pays for arrives with it: army value at t=180 up 46% (2,183 →
3,183) and unit count at t=360 up 30% (16.4 → 21.3). The bill is later income and a smaller
base: peak extractors 4.00 → 3.42 and structures at t=360 14.6 → 12.7.

**Why later income, when the bot takes its first site sooner** — and it is worth knowing,
because it is a property of the ladder rather than of this rung. Extractors past the first are
reached through the surplus branch's FALL-THROUGH, which fires when the bot is NOT in surplus.
The old bot reached income by being poor. One early extractor makes it less poor, so it falls
through less and spends more of its builder on throughput instead. That interaction is the
argument for the target being higher than 1, and it is exactly what the field exists to let a
search find.

**The knob has measured dynamic range in both halves.** At `income_structure_target = 4` the
bot takes its second site by t=120 rather than t=180 — and then stops at ~2.5, not because the
map is out of sites (there are twelve) but because by then it has SEEN the opponent and
`safety()` has bent its target down. That is the modulation working, observed rather than
asserted.

## Where a building goes

**The rule: placement is chosen in the BOT'S frame, never in the world's.** Two hard
constraints filter the candidates, a scored comparison picks among what survives, and no term
anywhere names an axis of the map.

The deployment drops are ranked by the same score (`BotDeployment`), anchored on the army
before the command centre exists — see
[starting-formations](../scenario-scripting/starting-formations.md) §Presentation and targeting.

### What was wrong, and how much it cost

`BotEconomy._find_build_spot` used to walk rings outward from the base centroid and return the
FIRST valid cell, scanning `for dx in range(-radius, radius + 1)` then `for dy` in the same
order. The first acceptable cell on a ring is therefore always the one furthest toward −X, then
−Z — **a preference in world coordinates, which does not mirror when the map does.** On a
provably point-symmetric map both commanders laid their bases out at a mean offset of dx ≈ −5
from their own start point instead of ±5, stopped being mirror images at tick 60, and never
were again. See [selfplay-results-2026-09-06](selfplay-results-2026-09-06.md) §The mechanism.

### The property wanted is EQUIVARIANCE, not symmetry

Two different things, and conflating them would produce a worse bot:

- **Invariant** means the choice must not depend on the world's axes. Apply an isometry to the
  bot's whole situation and its choice moves by that isometry: two bots in mirrored situations
  make mirrored choices, and rotating the map rotates the placement with it.
- **Asymmetric** means the resulting layout is not required to be uniform, and should not be.
  The bot may and does favour directions **relative to its own situation** — production toward
  the threat, everything else behind the base.

Equivariance is what holds both at once: the layout is expressed in a frame the bot carries
with it, so it can be as lopsided as it likes without the lopsidedness being about the map.

### The frame

`forward` is the axis the bot orients against, as a unit vector from the base centroid:

1. **the believed threat** — the nearest enemy structure it has actually SEEN, else the nearest
   enemy unit it remembers. Fog-limited on purpose, exactly as the attack objective is (§The
   attack objective is a belief): the bot orients against what it has found.
2. **the middle of the map**, before it has seen anything. An isometry of the map fixes the
   map's centre, so base→centre transforms with the map, and it is a fair proxy for "the
   contested ground" when nothing better is known.

`right` is its perpendicular. Every candidate is then described by how far ALONG that axis it
sits, how far LATERALLY, and how far from the base — and nothing else is ever read.

### The score

Cost, lowest wins, all in cells:

```
  COMPACTNESS_WEIGHT × distance from the base       the ruler; sprawl is the unit of the scale
− bearing            × distance along forward       production forward, everything else behind
− place_corridor_weight × min clearance in footprint   don't pinch your own lanes
```

`bearing` is `+place_frontage_bias` for a structure with a `Production` component and
`−place_shelter_bias` for everything else — classified by component rather than by a type list,
like every other classification in `BotEconomy`. **`COMPACTNESS_WEIGHT` is fixed at 1.0 and is
deliberately not a parameter**: the score is only ever compared against other candidates for
the same building, so multiplying every weight by one factor changes no decision and one term
has to be the ruler. That is the same argument that keeps THREAT out of `BotTargeting`'s weight
set — see [bot-parameter-space](bot-parameter-space.md).

The corridor term reads the MINIMUM clearance over the footprint rather than one cell's, which
is both the right question (the tightest point is what pinches) and the only mirror-invariant
one. It is capped at four cells, because without a cap it stops meaning "keep your lanes open"
and starts meaning "go stand in the middle of the map".

### Two details that are the whole of why it actually mirrors

**No random tie-break, and this is not an oversight.** A draw from the seeded `SU.rng` would be
reproducible across replays, which is the project's rule — but it would NOT be
mirror-consistent, because two bots drawing from one shared stream in interleaved order get
different numbers. A tie broken by a draw is a tie broken by think order, which is the
world-frame bug in another costume. Ties break on bot-frame `(cost, along, lateral)` instead;
`(along, lateral)` is the offset in another basis, so no two distinct cells share it and the
order is total. Candidates are packed into one integer quantised to 1/100 of a cell, so the
native sort IS the preference order and last-bit float noise — two mirrored bots agree on a
score only to within a few ULPs — cannot decide a tie.

**A candidate is a footprint ORIGIN, not a cell.** `Map.footprint_origin` resolves an EVEN
footprint by rounding in absolute grid coordinates, so two mirror-image cell CENTRES do not
resolve to mirror-image footprints — they land one cell apart. That is the same world-frame
preference as the ring scan, one layer down, and it showed up in a real match as a 0.707
residual between two otherwise exact mirror layouts. **`footprint_origin` was NOT changed**: it
is shared with the human player's build preview and placement, where the behaviour is merely a
snapping convention rather than a fairness problem, so **player placement still has it**. The
bot routes around it, because the set of footprint origins for a given `dims` IS carried onto
itself by the map's reflection. `tests/test_BotPlacementEquivariance.gd` sweeps base parities ×
1×1 / 2×2 / 3×3 to keep it that way.

### The hard constraints come first, and they live in the map layer

Before any scoring, a candidate is rejected if it would **split the walkable surface**, and
every structure the bot places must keep **a whole side on walkable ground** in the region its
own units stand on. Both rules are in `NavPlacement` (`scripts/maps/nav_placement.gd`) rather
than in the bot, because neither is a bot preference — they are facts about the map, and the
human player's placement validation wants the same answers. Nothing there reads a `Bot`, a
`Commander` or a difficulty.

The access rule is applied to EVERY structure the bot places, not only the ones that train
units: a building nothing can walk to cannot be repaired, garrisoned or deposited into either.
The narrower "production only" reading the feedback asked for is available to other callers as
`NavPlacement.accepts`' `a_needs_access` flag.

**A whole SIDE, not one adjacent cell.** A unit leaving a production building needs somewhere
to stand, and one cell poking out between two walls is not a way out.

### Why the connectivity check is cheap now

`TerrainGrid.placement_preserves_connectivity` answers the same question by flood-filling the
whole passable set TWICE per candidate. Profiled at **67–133 ms**, it was one of only 13 ticks
in 29,432 that blew the 33 ms frame budget — and the ring scan ran it on every candidate.

The observation that makes it local: blocking a footprint can only disconnect cells that were
connected THROUGH it, and every such path enters and leaves through a cell 4-adjacent to the
footprint — a GATE. So the placement is safe exactly when the gates can still reach each other
with the footprint blocked, which is a walk around a corner rather than a walk of the map. Two
things keep that honest: `TerrainGrid.component_at` labels the 4-connected regions so gates
that were never connected to each other are not asked to reconnect, and a `DETOUR_BUDGET`
bounds the worst case by REJECTING — the caller loses a candidate, never the map.

Measured on a 159×159 grid (the size of `skirmish.tscn`), 400 sampled 2×2 footprints, via
`tools/selfplay/_placement_bench.tscn`:

| | |
|---|---|
| `TerrainGrid.placement_preserves_connectivity` (the old check) | **76.0 ms/call** |
| `NavPlacement.preserves_connectivity` | **100 µs/call** |
| `NavPlacement.has_navmesh_side` | 16 µs/call |
| both rules together (`NavPlacement.accepts`) | 117 µs/call |
| region relabel, per `cells_changed` | 5.0 ms |
| clearance + distance fields, per `cells_changed` (pre-existing) | 12.5 ms |
| **one whole `_find_build_spot`, after a navmesh bake — the real case** | **6.3 ms** |
| one whole `_find_build_spot`, nothing changed since the last one | 1.3 ms |

The region labels get their OWN dirty flag rather than riding the clearance/distance one,
because the two have different customers: clearance and distance are rebuilt for every navmesh
bake, while labels are only ever asked for by a placement check. Sharing a flag would make
every bake pay for a relabel nothing was going to read.

**The expensive rules run on the CHOSEN candidate, not on every cell.** Scoring is O(1) per
candidate, so the whole disc is scored and sorted first and the navigation rules are applied in
score order, falling through to the next-best when one is refused — typically one or two
candidates deep.

### What it was measured to fix, and what it did not

**Equivariance, on the symmetric map** (`skirmish_symmetric.tscn`, re-verified at residual
0.000 under the point reflection before use; seed 1001, 200 s, per-second state dump):

| | before (ring scan) | after |
|---|---|---|
| mean offset of structures from own start point | dx **−4.96** and **−4.59** — both toward −X | dx **−3.75** and **+2.17** — opposite signs |
| mirror residual over structures present on both sides | — | **0.0000 at every sample** |

Every structure that both sides own sits at the EXACT point reflection of its counterpart. The
before column is the 2026-09-06 measurement; the after column is this build.

**Trapped units: none, over three full matches.** `tools/selfplay/_placement_audit.tscn` walks
a whole match and every simulated second checks the live terrain grid — the count of
4-connected passable regions, and whether every owned structure still has a whole side on the
main region. 1,020 checks over three matches (symmetric map seeds 1001 and 1004, `skirmish.tscn`
seed 7): **regions 7 at the first check and 7 at the worst, zero structures sealed in, zero
production structures sealed in.**

**The start-position bias SURVIVES, and that is the result worth arguing with.** Same design as
the published measurement — 8 seeds, MEDIUM mirror, 480 simulated seconds on the symmetric map,
each seed played with the start assignment both ways:

| | n | slot-1 margin positive | 95% CI (Wilson) | binomial p vs 0.5 | mean margin |
|---|---|---|---|---|---|
| A — authored assignment | 8 | **8 / 8** | [0.676, 1.000] | **0.0078** | **+9,706** |
| B — assignment swapped | 8 | 0 / 8 | [0.000, 0.324] | **0.0078** | **−10,006** |

Sign flipped on **8 of 8** paired seeds, so the advantage still follows the POSITION rather
than the slot index. Against the pre-fix 8/8, p = 0.0078, +10,189 on the same map and design,
**the placement scan was not the cause — or not the only one.** The 2026-09-06 note was
explicit that its attribution was "an observation plus a code reading, not a controlled
experiment"; this is the controlled experiment, and it says the reading was wrong.

**Where the surviving bias actually lives.** It is upstream of combat and it is not noise —
the split is an exact integer with zero variance across all sixteen matches:

| simulated time | structures, advantaged corner | disadvantaged | income structures | scout coverage |
|---|---|---|---|---|
| 60 s | 4.00 | 2.00 | 1.00 vs 0.00 | — |
| 120 s | 7.00 | 2.00 | 1.00 vs 0.00 | — |
| 240 s | 10.50 | 3.75 | 3.50 vs 1.00 | **0.430 vs 0.306** |

One corner reliably has an extractor committed by 60 s and the other reliably does not. The
per-second dump shows why: on the losing side a builder walks the length of the map on a
scouting errand while its partner stands still on a build that never completes, and the economy
freezes for ~90 s until the stall timeout releases it.

> **TODO — the leading suspect is `BotScout`'s frontier grid, which is a world-anchored
> quantisation and is NOT carried onto itself by the map's reflection.** `_grid_index_at`
> computes `roundi((local.x + _map_half_w) / SCOUT_GRID_SIZE)`; on this map that is
> `roundi(x/5 + 15.9)`, and `round(u + 15.9) + round(15.9 − u)` is not constant in `u`, so a
> point and its reflection land in buckets that are not mirror partners. The two commanders
> therefore partition the map differently, value frontier targets differently, and — measured
> above — cover 0.430 against 0.306 of it. **This is the same class of bug as the ring scan,
> one module over**, and it is the first thing to test against the start-position instrument.
> Anchoring the grid so its bucket boundaries are symmetric about the map centre is the fix to
> try. A second, smaller source: the opening deployment scatter draws from the one shared
> `SU.rng` in deploy order, so the two openings differ by ~0.3 world units from tick 30 — but
> that follows the SLOT, and the measured bias follows the POSITION 8/8, so it is a noise
> source rather than the cause.

## The bot works lithium ponds, not just extraction sites

**`_income_build_spot` considers both reservoirs and takes whichever is nearer the base.** Until
2026-09-12 it scanned the `extraction_site` group alone, so every lithium pond on a map was
invisible to the bot — half the energy economy, uncontested for a human opponent. Measured on
`skirmish.tscn` (two ponds): **0 of 2 worked after four simulated minutes before, 2 of 2
after.**

A pond is asked through `EnergyExtractor.fits_in_pond`, not `BotEconomy._placement_ok`, which
refuses submerged cells outright and so would reject every cell of every pond. Candidate cells
come from `WaterBody.basin.covered_cells()` filtered to the shallow ones; the one-per-body claim
is judged separately, from belief (§Income is found by scouting; see also
[water-bodies](../terrain-and-navigation/water-bodies.md) §One extractor per body).

**A pond an in-flight job is already aimed into is not offered again**
(`_ponds_under_way`). `_is_claimed_spot` cannot do that job — it is a RADIUS, and a pond is far
wider than it, so two jobs aimed at different cells of one body both pass it. A reservoir is
claimed whole or not at all. The engine abandons a duplicate on arrival regardless (see
[water-bodies](../terrain-and-navigation/water-bodies.md) §One extractor per body); this is what
stops the bot spending a builder walking to a job that will be thrown away.

> **TODO — a pond is priced with a ruler.** Distance is the whole comparison, matching what the
> site search already did, but a pond pays `POND_RATE_MULTIPLIER` times faster and is FINITE, so
> "which is worth more" is a genuine value-over-time question. It wants the same currency the
> ability and Servant-garrison questions want; see §What has to be modelled.

### Income is found by scouting

**Both searches are fog-limited: a site or pond cell the bot has never had in vision is one it
does not know exists** (`Commander.has_explored`). Until 2026-09-27 both read the whole map
from the first tick. This is the same stance as §The attack objective is a belief, and it puts
the same price on scouting: a bot that never looks never expands beyond the ground its own
base and builders have uncovered. A pond is offered at a cell the bot has seen, so a pond
glimpsed at its edge is workable from that edge.

**Whether a deposit is already worked is a belief too.** The bot reads a claim live only
when it is its own extractor or one in its vision; otherwise a site or pond counts as claimed
only if the blackboard remembers an enemy structure standing there, and the memory lasts until
the bot looks again. A deposit taken out of sight therefore still reads open. A builder sent
to one finds it taken on arrival, and `Build.fulfill_action` drops and refunds the order.
Arriving also puts the extractor in vision, so the blackboard learns the claim and the next
search skips it.

> **TODO — a pond's charge is still read live.** The bot knows a pond was drained out of its
> sight. A remembered charge needs a per-body memory the blackboard does not keep.

## Concurrent builds, and why the bot never co-builds

**`build_concurrency` is a real ramp: PASSIVE 1, EASY 1, MEDIUM 2, HARD 3, IMPOSSIBLE -1
(UNCAPPED).** It was 1 on every tier until 2026-09-12 — a constant wearing a parameter's
clothes, and a visible one: a Colonial opening pairs two Servants, and the second stood idle
for the whole match because nothing else in the bot claims an unarmed unit.

**-1 is the same UNCAPPED sentinel `production_structure_cap` uses, and it must never be read
as a count.** `maxi(1, -1)` is 1, so a raw read turns "uncapped" into the tightest possible
throttle, silently, and only on the hardest tier. `BotDifficulty.is_build_uncapped()` /
`build_slots()` keep that in one place, the way `preserves_unit_costing` does for
`preserve_min_cost`. The managers are pushed individual ints rather than the config object, so
those are statics taking the value.

**Raising the limit exposed what the limit had been hiding.** `tick()` picks ONE builder and
walks a priority ladder, and **a job that has been ORDERED but has not PLACED its structure yet
is invisible to every "do I own one of these" check in that ladder** — the structure does not
exist to be counted. So the second concurrent job re-ran the ladder from the top, reached the
same rung, chose the same spot, and put a second builder on the first one's site: both Servants
on one site, then both on one `Assemble`. An extra worker no longer shortens a build, so for
the bot that is pure waste. (Co-building remains a legitimate PLAYER mechanic; it is the bot
that has no use for it.)

Two guards, and the rate limit had been doing both jobs by never running a second build — its
own comment said so ("racing two builds onto the same cells"):

- **`_types_under_way()`** — the type an in-flight `Build` (its tool) or `Assemble` (its target)
  is raising counts as owned by the rungs that want exactly one of something, so the second
  builder falls through to the next rung and builds something else.
- **`_is_claimed_spot()`**, checked inside `_placement_ok` — the one gate every rung's spot
  choice already passes through, so a site another job is aimed at is unavailable to all of
  them. A radius rather than a real footprint overlap, because the claimed job's dimensions
  would have to be carried alongside its spot and being a cell too conservative only costs a
  slightly further site.

Tests: `tests/test_BotNoCoBuild.gd`, and the ramp itself in `tests/test_ScenarioPlayerSlots.gd`.

## A build that never finishes

**`BotEconomy.tick()` returns at the very top while `build_concurrency` jobs are in flight, so
a `Build` that can never complete does not waste a builder — it freezes the whole economy.** No
capacity, no infrastructure, no income, for the rest of the match, while the bank fills with
energy the bot cannot spend. This is `BotScout`'s unreachable-waypoint bug one module over: an
order that can never arrive never goes idle, so nothing ever releases the unit.

It was always there and was latent, because the pre-2026-09-05 ladder reached for an extraction
site only when it was too poor to do anything else — the same reason `economy_reserve` appeared
to work ([bot-economy-diagnosis](bot-economy-diagnosis.md)). Making the income rung fire early
made it common: an instrumented match had one side take the "already building" exit on **537 of
539 think passes** after claiming its second site, with its structure count frozen at 3 for five
simulated minutes and 8,000 energy banked. Five of twelve slot-trajectories froze for 90–270 s
where the previous ladder never froze for more than 30.

`BotEconomy._release_stalled_construction` abandons a job that has held a slot past
`CONSTRUCTION_JOB_TIMEOUT_SECONDS` (90 s) and **remembers where it was aimed**
(`_abandoned_spots`), which the second half is not optional: without it the rung that chose the
bad spot picks it again next think and a permanent freeze becomes a 90-second loop that spends
the builder forever. A TIMEOUT rather than the scout's distance-over-time test, because a
builder standing still at its site is what constructing LOOKS like. Clearing the command is
also what refunds the purchase — `BotActuator.build` registers it on the production queue with
the command as its holder. Longest frozen-while-rich stretch fell from 270 s to 90 s, the
timeout itself, and peak extractors recovered from 2.67 to 3.42. Cover:
`tests/test_BotConstructionStall.gd`.

**One of the two suspects is now closed, and the guard still earns its place.** The builder
that never started a job was `Movement._resolve_movement_target` casting an Extraction Site as
a `Commandable` when it is a plain `Entity` — a structure need not be commandable, so the cast
failed silently and the builder never resolved a target. That is fixed (2026-09-10, by the
author), and placement itself can no longer strand a builder either: §Where a building goes
rejects any spot that would split the walkable surface, so the bot cannot wall its own builder
into a pocket.

**Keep the timeout anyway.** What can still make it fire:

- a spot that becomes unreachable AFTER the order — another building goes up across the only
  approach, terrain changes, a bridge is destroyed;
- the footprint occupied between the order and the arrival, by a structure or by a unit parked
  on it;
- a builder wedged in an avoidance crowd, which from outside is indistinguishable from a
  builder standing at its site building.

The asymmetry of costs has not moved: the failure it guards against freezes the ENTIRE economy
for the rest of the match, and the guard costs one builder-minute when it misfires. It is still
observable — in the 2026-09-11 symmetric-map corpus the losing side sat on two structures for
roughly 90 s before the timeout released it, which is the guard doing its job on a cause that
is not placement (see §Where a building goes, on where the surviving start-position bias
lives).

> **TODO — two things about it are now the weaker half.** With the builder bug closed, the most
> likely way to trip it is a legitimately SLOW build: a slow builder plus a long build time
> crossing 90 s is a false positive, and a false positive is expensive because
> `_abandoned_spots` never expires, so one blacklists a good spot for the rest of the match. If
> the timeout is kept as-is, `_abandoned_spots` probably should not be permanent; if the spots
> stay permanent, the timeout probably wants to be a function of the structure's build time
> rather than a constant. Neither has been measured.

## Dominion routes

**Which pieces earn a faction dominion is the faction's own answer, never a component the bot
looks for.** Each faction scene carries one `DominionRoute` node — its dominion mechanic — and
`Bot.dominion_route()` finds it. The bot asked before whether a building carried a
`DominionGenerator`, which a commander-level sweep (the Opticon's, the Warlord's) has no building
to carry, so a Libertarian bot never built an Opticon.

What a route answers, and who does what with it:

| faction | route | structure sources | site-dependent |
|---|---|---|---|
| Colonial | `DominionRoute` (the base) | the Compound | no — one is as good as another |
| Libertarian | `LibertarianDominion` | the Opticon | yes — a tile two Opticons see pays once |
| Anarchist | `AnarchicalDominion` | none — the Warlord is trained | — |

`BotEconomy` builds the FIRST source at the top of its ladder, as it always built the Compound.
A site-dependent route is also surveyed: a lattice of candidate sites around the base, each
scored by the fraction of a lone source's income it would add, less a cost per cell of distance
and of exposure toward the believed threat. The survey is resumable across thinks and memoized
until the bot's structures change. Once in surplus, the bot builds ANOTHER source while its best
site still adds at least `MIN_DOMINION_SITE_FRACTION` — ahead of production capacity.

TODO: every weight here is a placeholder, and the threshold is really the energy-against-dominion
question (bot-roadmap.md) in disguise.

TODO: the planned routes each need a question the base does not ask yet — a Marxist route pays
for DESTROYING structures (its own infrastructure provider included, at a worse rate), a
Technocratic one is restricted to extraction sites and trades against an extractor, and a unit
route (the Warlord) is not valued by BotProduction at all. Each adds its own query to
`DominionRoute` when it is built.

## The utility unit count follows the work

**How many builders and carriers the bot keeps is one per live ERRAND, not a constant.**
`BotProduction._utility_demand_for(type)` adds, for the errands that type can serve: one
builder per concurrent build job (`build_concurrency`), one carrier per capturable cluster
(`Bot.capturable_clusters`, and zero while the bot owns nowhere to bank prisoners — the same
gate `BotOpportunist._gather_captures` applies before it will dispatch anyone), plus one spare.
`BotDifficulty.utility_unit_cap` bounds the answer.

It replaced a flat 3 per type, which was both floor and ceiling: the bot built a third Stock
Truck when three armed units would have served it better, and would never build a fourth when
the capture loop was the best energy on the map. A utility unit with no errand is the whole
definition of "too many", and every input already existed.

Two terms exist because of things that changed after the question was asked, and both stop the
model UNDER-building:

- **Scouting is an errand too**, and since the attack objective became fog-limited it is the
  errand the whole offensive waits on. It belongs to the POOL rather than to a type — any spare
  body can take it — so it raises a type's allowance by one only while the pool as a whole is
  short of `scout_unit_budget`, rather than being counted once per type.
- **A crusher is army as well as errand.** `BotMilitary._combat_units` claims anything with
  combat utility, so a Stock Truck between capture errands is in the attack wave rather than
  standing idle; an extra one is not waste, and it gets one more.

Asked of the TYPE rather than of an instance, because production is deciding whether to MAKE
one and has no instance to inspect: `Bot.unit_type_can_build` / `unit_type_can_capture` /
`unit_type_can_crush` / `unit_type_has_combat_utility` read the build preview exactly as
`unit_is_utility` and `unit_can_attack` already do, so a new utility unit classifies itself.

Measured over the same six seeds: peak utility units 6.00 → 5.83 and the count at t=360 5.83 →
4.92, with army value slightly UP — a modest change, and modest is the honest reading. On
Colonial content the pool is two types out of one building, so the constant was not far from
the demand; what changed is that it now moves with the work instead of standing still. Cover:
`tests/test_BotUtilityDemand.gd`.

## When a side is beaten

**No structures and no production is a defeat**, in the shipped game and in the self-play
harness alike, and it is `Commander.has_production_base()` in both. Units alone are not a
comeback: a commander with no buildings cannot train, cannot expand, and the corpus that made
the case has the number — 23 of 61 stalemates were one side at zero structures riding a single
straggler to the clock. PRODUCTION and not just structures, because a funded Build whose
builder is still walking IS a base being rebuilt.

`Scenario._check_player_eliminated` runs this clause and the older owns-nothing clause
together, each behind its own arming latch, so a mission that opens with units and asks the
player to build a base is not lost on frame one. See
[selfplay-harness](selfplay-harness.md) §No structures and no production is a defeat.

## Difficulty is a knob

`BotBrain.config` is a `BotDifficulty` — one flat data object per tier, selected by
`set_difficulty` and pushed into the managers by `_apply_config`. **Numbers, not branches**,
so a tier can be searched by a tuning run and every other parameter held equal while one
moves. The tier VALUES are hand-made placeholders; the knobs they name are settled. See
[bot-roadmap](bot-roadmap.md) §Difficulty first.

Tests: `tests/test_BotSanction.gd`,
`tests/test_BotHostileTargets.gd` (whom the bot may attack, and that it must have SEEN them),
`tests/test_BotCombatUtility.gd` (armed or able to crush), `tests/test_BotKamikazeHold.gd`,
`tests/test_Elimination.gd` (both defeat clauses),
`tests/test_BotScout.gd` (scout suitability + the scouting trade-off),
`tests/test_BotMomentum.gd` (the winning/losing signal and the retreat it drives),
`tests/test_BotClusters.gd` (grouping and coverage), `tests/test_BotDebugOverlay.gd`,
`tests/test_ScenarioPlayerSlots.gd` (the difficulty ramp's direction).
