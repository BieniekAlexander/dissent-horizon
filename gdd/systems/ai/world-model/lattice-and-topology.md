---
title: The lattice and the map's topology
type: system-note
---

# The lattice and the map's topology

*Design note for [Dissent Horizon](../../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

**PLANNED — approved 2026-10-08, awaiting the instruction to build.** How the bot represents
SPACE: one coarse lattice over the map carrying the L2 channels, and DISTANCE FIELDS over
passable ground that make "an approach", "reachable, but not in time" and "a risky path"
reads rather than searches. Scoped 2026-10-08 against every system it touches (`/scope`); each
decision below is Alex's and is dated where it was made. Work item: `gdd/tasks.md` T-101. The
layers that read this are [layers](layers.md) §L2 and §L3; the purchase-side consumer is
[macro-learning](../macro-learning.md) §2 (the threat clock); the placement consumers are
[squads-and-relations](../squads-and-relations.md) §Placement beyond open ground.

## What exists today is radial, not topological

Every spatial sense the bot has is a vector or a disc: `Bot.threat_direction` is one axis,
`Bot.base_threats` is a `defend_threat_radius` disc around each structure,
`BotEconomy._defence_demand` is a `DEFENCE_REGION_RADIUS` disc, `Bot.is_reachable` is one
navmesh query, and `BotScout._expected_sightings` samples a STRAIGHT LINE between two points
and calls it the corridor. None of them can say that the back of the base is quiet because
it is far along the ground, that a raid will arrive before the guard can, or that the short
road runs through the enemy's army. The map layer already holds the primitives those reads
need — `TerrainGrid.navigable_mask` per size class, its 4-connected component labels, the
clearance and distance-to-obstacle fields, and the gate walk in `NavPlacement` — and nothing
in the bot reads them as a field.

## One lattice

**One lattice.** Today three quantisations of the same ground disagree: the scout grid (5
units, world-anchored with `roundi`, hence the mirror asymmetry at
[bot-architecture](../bot-architecture.md) §What it was measured to fix), the dominion survey's
lattice (5 cells, centred on the base), and the build-spot search's disc. They become ONE
grid-geometry object — pitch 5 world units, origin at the map centre, world↔index — carrying
several CHANNELS, and every consumer reads it. The channels, each recomputed from tracks on
its cadence rather than accumulated, each piece stamping a disc bounded by its reach:

| channel | definition | reads it answers |
|---|---|---|
| `sight_age` | seconds since the cell was last fog-clear | stale, never seen; the unexplored fraction |
| `own_influence`, `enemy_influence` | Σ over pieces with lethality of energy value × confidence × falloff over (reach + speed·τ), τ the combat period | who controls here; the front, where own ≈ enemy and both are high |
| `threat` | Σ dps of enemy weapons that can REACH the cell, stored PER DAMAGE TYPE (a handful of channels); a unit reads its own threat as Σ_type dps × `DamageTable` multiplier against its armour — relational without a channel per armour class | standing here costs this much HP per second; retreat destinations |
| `tension`, `vulnerability` | own + enemy; tension − \|own − enemy\| | where fights happen; contested ground |
| `value` | resource sites, dominion sites, shelters, structures by energy value, per side | what is worth taking, holding, or hitting |
| `approach` | the APPROACH BAND (§Distance fields): cells on a near-shortest walk from a believed enemy source to the bot's own structures | approach coverage ([squads-and-relations](../squads-and-relations.md) §Placement beyond open ground) |
| `avoid` | lingering area effects publish into it; a cost term in the fields below | the avoid-region signal ([bot-roadmap](../bot-roadmap.md) §The gaps in the decision surface) |
| `combat` | witnessed damage stamped at its cell, decayed per period | engagements ([layers](layers.md) §L3) |
| `reach_coverage` | for a candidate cell and a weapon reach: the fraction of the reach disc that is passable ground on an `approach` | whether a static defence placed here guards anything |

The derived reads over them, stored too: an **undefended approach** (high `approach`, low
`own_influence`); a **safe build spot** (low `threat`, high `own_influence`, high
`reach_coverage` for a defence); an **exposed enemy position** (high enemy `value`, low
enemy `threat`, low `enemy_influence` — many structures, no weapons, nothing defending);
and its mirror, the bot's **own exposure** — the same read over its own structures, which is
where units and static defences belong. The clustered turrets whose ranges covered cliffs
(observed 2026-10-06) score near zero on `reach_coverage`, which is the placement the read
rejects.


## Passability is relative to the agent, and fog-limited

**One passability mask per size class, computed lazily** (decided 2026-10-08): the lattice
asks `TerrainGrid.navigable_mask` for a class the first time a field for that class is wanted
— the bot's own classes, and the classes it believes the enemy fields — and never for the
rest. A LARGE truck's quiet flank is a SMALL raider's front door, so one permissive mask would
mis-price every narrow route.

**Passability reads the TRUE grid, and no destination is ever predicated on it** (Alex,
2026-10-08, superseding the first ruling that unexplored ground was impassable). The known
RTS exploit decides it: a player can order a unit into the fog and the unit walks around every
obstruction there, terrain and unseen structures alike, so the map's topology is obtainable by
probing and the bot is handed it rather than made to probe. So the fields sweep the whole
grid, explored or not, structures included, and a believed source always has an arrival time
wherever it is connected. What stays fog-limited is the OTHER half of every spatial read: the
sources are beliefs, and **a point the bot orders a unit to must be one it has explored** —
`BotFields.is_explored` is the gate every stage point, post, objective and waypoint passes
through. That keeps the player's own shape: the pathfinder knows the ground, the player can
only click what they have seen.

**The lattice's coarseness is an accepted bias** (Alex, 2026-10-08). A cell is passable when
at least half the terrain cells under it survive the class's erosion, so a thin wall through
a block can read passable and a one-cell corridor can read sealed. That is signal
degradation, not a defect to engineer away: the bot's behaviour does not turn on it.

**Where the information is missing, the PERSONALITY fills it** (Alex, 2026-10-08). With the
true grid under the fields, the information that can be missing is the SOURCE: before any
sighting there is no believed enemy to measure from, so the clock cannot be computed, and the
game means it that way: fog is what makes the meso layer a game of
limited information ([design-framework](../../../design-framework/README.md) §Micro, meso,
macro). With perfect information the macro counter is a solved rock-paper-scissors — static
defence beats a rush, income beats static defence, a rush beats income — so what a bot does
without the information is a DISPOSITION, not a derivation. The bot already holds one such
prior for the enemy's unseen SIZE, `assumed_enemy_parity` ([bot-parameter-space](../bot-parameter-space.md));
the clock gets its spatial twin — **as a role of the POSTURE VECTOR** (decided 2026-10-08,
option 3 of the T-101 question): the `risk` and `aggression` dials of
[objective-selection](../objective-selection.md) say how near the bot assumes an unseen
threat is and how soon it assumes first contact, so a turtle assumes the raid is near and a
greedy bot assumes it has time, and the population's mixed equilibrium
([bot-randomness](../bot-randomness.md)) is where the rock-paper-scissors is played out. Not
new `BotDifficulty` fields: a detour factor and an assumed first-contact time were offered and
declined in favour of the layer that will own every such disposition.

> **TODO — the clock before any sighting waits on the posture layer**, which is itself
> unapproved. Until it exists, an arrival time with no believed source to measure from is a
> typed MISSING read, and every consumer keeps the radial sense it uses today in that case.
> Status quo, not a fallback chosen here. (The first form of this question — a route across
> unexplored ground — dissolved when the fields were allowed the true grid.)

## Distance fields: the topology primitive

**A Dijkstra distance field per source set over the lattice's passable cells, stored as
scalars** (decided 2026-10-08 over sampled navmesh paths and over a chokepoint region graph).
One sweep answers every destination at once; the field IS a flow field — descending its
gradient from any cell gives the cheapest route to the nearest source — and it is coarser
than the terrain grid by construction. A region graph in the Brood War Terrain Analyzer
style was considered and set aside: this game's terrain is open and its chokepoints are not
well defined, so a chokepoint is not a primitive here but a READ — the place where the
approach band below is narrow.

**The computation lives in the map layer** (decided 2026-10-08), beside `NavPlacement`, as a
pure class taking a navigable mask, a set of sources with a per-source start cost, and an
optional per-cell cost multiplier, and returning one distance per cell. It is a fact about
the ground, not a bot preference, which is why it is reusable by the player's HUD (an
arrival estimate for a pending piece, `gdd/tasks.md` T-068) and by mission tactics; the bot
owns only WHICH sources are believed. Costs are INTEGERS — orthogonal 10, diagonal 14, a
penalty scaled to the same units — so two mirrored bots compute bit-identical fields and
"mirror-exact" is a byte comparison (§Determinism).

**Sources.** Enemy fields are sourced on the believed enemy GROUPS ([layers](layers.md) §L2)
and believed enemy structures; the home field on the bot's own structures. One field per
(size class, source set), refreshed on its cadence as a resumable sweep.

**Allied presence is a penalty on the enemy's field** (Alex, 2026-10-08). An allied army is a
challenge to the enemy's movement, so the cost of a cell on the enemy's field rises with the
bot's own `own_influence` there: the enemy's expected route bends around the bot's forces, and
the approach band moves when the army does. The penalty weight is a model constant to start;
whether it is worth a difficulty parameter is for the search to say.

The reads, each stored on the model:

- **`arrival_time(cell, group)`** — the group's field distance at the cell ÷ its slowest
  member's speed. The threat clock ([macro-learning](../macro-learning.md) §2) is this against
  the time an answer takes to field.
- **The approach band** — cells whose enemy-field distance plus home-field distance is within a
  slack of the minimum of that sum: the ground a walk from them to us would plausibly cross.
  Its width at a point is how constrained the approach is there — the chokepoint read — and
  `reach_coverage` for a static defence is the fraction of the band inside the weapon's reach.
- **Quiet ground** — cells reachable but with an arrival time beyond a horizon from every
  believed source: physically accessible and not realistically so, which is what the rear of a
  base is. Both reads are kept (decided 2026-10-08): the band places a defence, arrival time
  prices a threat, and they disagree exactly where a flank route exists.

**Risk-weighted routes change what the bot DECIDES, not how its units walk** (decided
2026-10-08). The stage point, a retreat destination and the direction an objective is
approached from are chosen on the weighted field; the orders issued are ordinary Moves through
`BotActuator`, which walk the navigation mesh as they do today. Routing by the field — a
waypoint chain handed to the Move — is the form T-092 (the avoid-region signal) takes if it
lands on the bot's side rather than in pathing, and is not built here.

> **REJECTED (2026-10-08) — navmesh region costs as the risk channel.** Checked against the
> Godot 4 reference: `NavigationRegion3D.enter_cost` and `travel_cost` are properties of a
> REGION, applied in every query on the map, and `NavigationPathQueryParameters3D` offers no
> way to ignore them — only `navigation_layers`, `included_regions` and `excluded_regions`.
> A cost-aware and a cost-free query over the same ground would need the ground baked twice
> into regions on separate layers, which the project already spends on size classes. The
> lattice answers the decision-side question without touching the navmesh; if T-092 ever
> wants navmesh costs, it is a separate region set and its own note.

**Aircraft** (decided 2026-10-08): an aerial source's travel time is Euclidean at its air
speed from the same believed positions, and air threat is the subset of weapons whose target
mask reaches the air layer — two more channels, with no band, since every direction is an
approach for a flyer. Whether the bot FIELDS aircraft is still [bot-roadmap](../bot-roadmap.md)
§The gaps item 4; defending against the enemy's needs no answer to that.

## Defending assets across space

Structures cannot move and units move at different speeds, so "what to defend" and "with
what" are two reads, and both are arrivals against a clock.

- **What is worth defending** is `value × vulnerability`, as the defence demand already
  computes on presence (`BotEconomy._defence_demand`), read per lattice region once the
  channels exist. **`value` is the piece's `Bot.unit_cost` for now** (decided 2026-10-08): a
  nuanced long-term value — an extractor's income stream, a producer's output, a tech
  building's unlock — is another body of work, and the trivial price keeps this note's
  mechanism independent of it. TODO: the stream value, once an energy-against-dominion rate
  exists (`gdd/tasks.md` T-049) and the state value of [macro-learning](../macro-learning.md)
  §3 can price it.
- **Who answers a threat** gains an ARRIVAL TERM (decided 2026-10-08, built the same day:
  `BotMilitary._arrives_in_time`): the guard is drawn best-matchup-first as today
  ([squads-and-relations](../squads-and-relations.md) §Squads, the guard), but a unit counts
  toward it only if its arrival time at the worst-threatened structure — read off a field
  sourced at the structure's cell, for the unit's class (`BotFields.arrival_seconds_between`)
  — is below the structure's time to kill under the threats on it (`Bot.time_to_kill`). A
  unit that arrives after the building has fallen is worth nothing there, whatever its
  matchup.
- **A defended post is a `HoldPolicy` at a point the model picks** (decided 2026-10-08):
  the band's narrowest cell inside the bot's own influence, or the threatened structure.
  `Defend` and `Patrol` are out of scope for bots (Alex, 2026-10-08, T-002): they are
  conveniences over unit aggro offered to the player, and the behaviour underneath them is
  already the bot's.

## Difficulty

Built 2026-10-08. `field_refresh_seconds` is a PERIOD — the cadence of the fields job, set
per tier (PASSIVE 6 s to IMPOSSIBLE 1 s) and, like every period, never jittered or searched,
since reaction time is the tier's identity ([bot-randomness](../bot-randomness.md)); the
first draft of this section had it searched, which that rule forbids. Two numbers are
SEARCHED, appended at the END of `SEARCH_RANGES` so the roster's draw order is kept
([bot-parameter-space](../bot-parameter-space.md)): `arrival_margin_falloff_seconds`, how
much margin before a threat stops weighing on what the bot buys (the threat clock's shape),
and `place_coverage_weight`, how many cells of sprawl a static defence's full coverage of
the band is worth. The quiet-ground horizon, the band slack, the presence penalty's rate
and the clock's floor are model constants.

**`should_use_fields`** (built 2026-10-08) is the switch that compares a tier against itself:
off, `Bot.fields()` is null and every consumer keeps the rule it had before the fields
existed. A first A/B switched the fields JOB off instead and measured a bot whose first,
empty snapshot never refreshed — no band, every believed unit at the clock's floor — which
is a degenerate bot, not the old one; those twelve matches are discarded. The switch is the
precedent `should_use_learned_production` set.

## Determinism

**Store distances, never paths** (decided 2026-10-08). A field is a scalar per cell computed
in integer arithmetic, so neighbour-expansion order cannot leak a world axis into it — two
mirrored source sets give mirrored fields to the bit — and every set the bot derives (the
band, quiet ground, the post) is a function of those scalars. The lattice is anchored on the
map centre, which retired the scout grid's `roundi` world anchor (2026-10-08), the suspected
cause of the start-position bias — whether the bias moved is not yet measured — ([bot-architecture](../bot-architecture.md) §What it was measured to fix).
The test is a mirror residual of 0.000 per channel on the symmetric map
(`tests/test_BotPlacementEquivariance.gd` is the model), run against a fixture, not a scene.
Replays are unaffected: a bot's orders are re-derived from the seed and the fields are a
function of its own sightings.

## Performance

`skirmish.tscn` (220 world units across) at a 5-unit pitch is a 44 × 44 lattice, 1,936
cells. **Measured 2026-10-08** (M-series Mac, headless, 30% walls, eight sources): one
`NavField` sweep over it costs **8.5 ms**; the presence penalty over forty stamps 0.4 ms; a
whole `BotFields.refresh()` followed by every read costs **13 ms with nothing believed**
(the home field plus the explored mask) and **48–54 ms once enemies are believed** — the
enemy field, the home field and one arrival field per believed (class, speed) pair, five or
six sweeps. That is more than a tick, so the fields job (step 4) spreads the sweeps over
ticks on the scheduler's work-unit budget — `NavField.run` already settles a bounded number
of cells per call — and refreshes on `field_refresh_seconds`, never per think; and the
per-speed arrival fields want bucketing to the speed ladder if believed speeds multiply.
Measured per channel before the next lands is [migration](migration.md) §Cadence and
cost's standing rule, and this is its first entry.

**With the consumers live (step 4, 2026-10-08):** the same 180 s MEDIUM mirror ran at 149
ticks per wall second with the fields only sampled, 132 with the job and every consumer on,
and 140 once a believed type's mobility was cached per snapshot (the clock had walked every
piece in the tree for every believed unit on every demand-map call). Single matches whose
trajectories differ, so the residual is a bound, not a cost. What still sweeps OUTSIDE the
job's budget, each a TODO to move behind it if it shows in `BotScheduler.report`: the point
fields the guard's arrival term and the clock read (one per destination cell and class per
snapshot, `BotFields._point_fields`), and `reach_coverage` for a defence placement.

> **TODO — precomputing the static half at map generation.** Passability per class and the
> static part of a field could be derived when a map is generated and stored with it (Alex,
> 2026-10-08: "if it's worth it"). Not built while the live sweep fits the budget: believed
> structures change the mask during a match anyway, so only the terrain part could be stored,
> and the saving is a measurement away from being known.

## Debug

Each channel is a heat map layer on the bot debug overlay — [debug-signals](../debug-signals.md)
already lists them as not built, with the scout grid's marker as the template — plus the
approach band, quiet ground and the chosen post, so a wrong field is seen rather than inferred
from a wrong order.

## Measured

**48 matches, 2026-10-08/09: the consumers neither win nor lose on `skirmish.tscn` at MEDIUM,
and the "slot bias" the first batch showed was the start point, with the personality draw on
top of it.** All three batches are MEDIUM Colonial mirrors with the fields off
(`should_use_fields: false`) on one slot, 900 s cap, no errors; rows are the session's scratch
`fields_*_results.jsonl`.

| batch | matches | fields on : off | slot 1 : 0 | second start point wins |
|---|---|---|---|---|
| seeds 11–13, each from both slots and both start points | 12 | 6 : 6 | 10 : 2 | 8 of 12 |
| the same seeds, `personality_spread` pinned to 0, on the later map | 12 | 6 : 6 | 6 : 6 | 12 of 12 |
| one seed per match, seeds 21–44, slot and swap cycling | 24 | 13 : 10, one stalemate | 11 : 12 | 18 of 23 |

Read per start point in the third batch, the on side won 10 of 12 from the second point and 3
of 11 from the first: the point decides, the fields do not. What read as a slot bias in the
first batch is two things. **The map has a stronger side, as an authored map may:** `skirmish.tscn`
is not symmetric and is not meant to be, and with the jitter pinned the second start point won
every match (the map on disk changed between the first batch and the other two — the tick-zero
digests say so — so the pinned batch is not a one-variable contrast with the first; both
versions have the same shape). Whether that edge is the ground's or a residue of the bot's own
start-position bias ([bot-architecture](../bot-architecture.md) §Where a building goes) needs
the symmetric control copy of [selfplay-results-2026-09-06](../selfplay-results-2026-09-06.md),
which is not in the tree today — the generator's PLANNED symmetric mode replaces it ([map-generation](../../terrain-and-navigation/map-generation.md) §Symmetric maps). **And a seed is a draw per slot, not per match:** a brain is
seeded from the match seed and its commander id, so the four matches of one seed hand slot 1
the SAME personality whichever condition or point it holds — three seeds were three draws, and
in two of them slot 1's draw beat the side even from the weaker point. Forty-eight matches
cannot see a ten-point edge either ([macro-learning](../macro-learning.md) §1 needed about
200); what they establish is that the fields change the bot's play without breaking it, at the
throughput cost §Performance records. The next measurement is a counterbalanced run with the
spread pinned or one seed per match — the harness's `swap_start_points` cancels the map's side
for the condition tally, which is what an A/B reads, but never for a per-slot read.

> **TODO — the constants are untuned.** The presence penalty's rate, the band slack, the
> quiet horizon, the clock's floor, the coverage weight's default and the falloff's default
> are starting values; the roster search can move the two parameters, and the model
> constants want a decision sim each before anyone moves them by hand.

## Build order

1. Built 2026-10-08 — the map-layer field class, `NavField` (`scripts/maps/nav_field.gd`):
   octile integer costs, the corner rule, sources on impassable ground, the entry penalty, a
   resumable sweep, and bit-exact mirroring. Cover: `tests/test_NavField.gd`.
2. Built 2026-10-08 — `Lattice` (`scripts/maps/lattice.gd`), the map-centred geometry whose
   cells reflect onto each other, and `BotFields` (`Bot.fields()`), which lays one over the
   map and builds the true-grid passability mask per size class, lazily, memoizing the
   terrain mask until the grid's cells change, with the explored set as a separate mask that
   gates destinations. `BotScout`'s grid now has one point per lattice
   cell and indexes through it; its timestamps are the `sight_age` channel
   (`BotScout.sight_age_at`) until a second reader wants them on `BotFields`. Cover:
   `tests/test_Lattice.gd`, `tests/test_BotFields.gd`. The dominion survey and the build-spot
   search still quantise on their own ([migration](migration.md) step 3's remainder) — TODO,
   with step 3 here.
3. Built 2026-10-08 — the fields on `BotFields`, every one a lazily built function of beliefs
   dropped by `refresh()`: `enemy_field` (every believed enemy position, penalised by the
   bot's own armed presence), `home_field` (own structures), `approach_band`,
   `arrival_seconds_at` (ground units along their class's field at their type's speed, read
   to beside a walled cell; aircraft on the straight line), `is_quiet_at`, and
   `presence_penalty`. `Bot.mobility_of_type` carries a believed type's speed, class and
   whether it flies. The pure rules are statics (`sweep`, `band`, `arrival_seconds`,
   `presence_penalty_of`), covered by `tests/test_BotFields.gd`. Probed on `skirmish.tscn`
   (180 s, MEDIUM mirror): the band appears once an enemy is believed (7–25 cells), the
   arrival time at the base reads 13–18 s, no errors. Not built here: the air THREAT channel
   (weapons with an air mask), which is the general `threat` channel's business.
4. Built 2026-10-08 — the fields JOB (`BotBrain` job `fields`, priority above every
   decision, on `field_refresh_seconds`): `BotFields.refresh()` begins a rebuild and
   `advance()` carries it on within the scheduler's allowance, each sweep settling a bounded
   number of cells per call, behind a complete snapshot that reads serve until the new one
   swaps in (work units calibrated from the 2026-10-08 measurement). The consumers: the
   station and stage points stand on the band (`BotFields.approach_post`, ties broken in
   the bot's frame); the guard's arrival term; a static defence's placement score gains
   `reach_coverage` over the band (`BotEconomy`, weighted by `place_coverage_weight`); and
   the threat clock weighs every believed enemy UNIT in both the demand map and the learned
   valuation's composition (`Bot.clock_weight`, `Bot.believed_enemy_composition_clocked`,
   against `Bot.fastest_answer_seconds`). Cover: `tests/test_BotFields.gd`,
   `tests/test_BotStaging.gd`, `tests/test_BotPlacementEquivariance.gd`,
   `tests/test_BotThreatClock.gd`. Not done: the defence DEMAND is still per presence disc
   (`BotEconomy._defence_demand`'s TODO); only its placement reads the band.
5. Built 2026-10-08 — the difficulty parameters (step 4); the `Fields` category of the bot
   debug overlay (`BotDebugFieldsLayer`: band tiles, arrival shading, the presence outline,
   the post; [debug-signals](../debug-signals.md) §Fields); and three decision sims under
   `sims/bot/fields/` ([decision-sims](../decision-sims.md) §fields/): the army stages on the
   approach and the turret covers the band are green, with the turret's zero-weight control
   red; the guard's arrival sim is specification-red until a slot can start with a wave out.
   The `placed` check was added for the turret. The self-play A/B of the consumers against a
   bot with the job off is §Measured below.
