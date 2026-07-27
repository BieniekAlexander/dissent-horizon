---
title: Self-play results 2026-09-06
type: system-note
---

# Self-play results 2026-09-06

*Design note for [Dissent Horizon](../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

**MEASURED (2026-09-06).** 156 matches, 5.4 core-hours, 20.0 simulated hours, on the
[selfplay-harness](selfplay-harness.md) with the
[bot-economy-diagnosis](bot-economy-diagnosis.md) fixes in place. Two questions: is the
start-position advantage the 2026-09-05 corpus hinted at real, and does the parameter space
read differently now that both bots have an income. The 2026-09-05
corpus it re-measures had a bot with zero income; where a result here differs from it, it
says so. Raw rows and every analysis script are in `tools/selfplay/results/`.

## The verdict

**The start-position advantage is real, it is enormous, and the map is not what causes it.**
On a true MEDIUM mirror the slot at StartPoint1_mirror leads on material in **16 of 16
seeds** (p = 3.1 × 10⁻⁵); exchange which slot deploys at which start point and the lead
follows the POSITION in 15 of those 16. But it survives geometry: a numerically exact
symmetric copy of the map — max height residual 0.000, 0 of 12,641 tile cells differing,
every authored entity its own reflection's partner — reproduces the same advantage at the
same size (8/8 seeds, +10,189 mean material), still following the position. The cause is
`BotEconomy._find_build_spot`, whose ring search returns the first valid cell scanning −X
then −Z, so **both commanders build toward the same world axis instead of mirroring each
other**; measured on the symmetric map, both bases' structures sit at a mean offset of
dx ≈ −5 from their own start point rather than at ±5. **Fixing the map would have fixed
nothing**, and the symmetric copy is worth keeping only as the control that proved it.

**Three of the eight bit-identically inert parameters came alive, five did not.**
`economy_reserve = 1500` and `demand_coverage_falloff = 0.0` now produce their own
trajectories in 4 of 4 replications each — the [bot-economy-diagnosis](bot-economy-diagnosis.md)
prediction confirmed. `preserve_min_cost = −1` moves the simulation late (first divergence
at 260 s) and tinily. `army_commit_threshold`, `preserve_min_cost = 0`,
`wave_abort_fraction` and `defend_threat_radius` are still bit-identical at both ends: the
economy fix did not reach them, and they are still not reachable from a MEDIUM mirror.

**The archetype matrix is still cleanly transitive, but the ordering moved.** ECONOMIST
still wins everything (Bradley-Terry +0.459) and there is still **no cycle** — R² = 0.975
over 40 matches, two seeds, both sides. What changed is the bottom: **RUSHER is now last**
(−0.625), where it used to be third, and **MEDIUM is no longer last**. The intransitivity
you were hoping for is still not there, and the working economy did not create it.

**And the honest caveat that shapes everything above: not one of the 144 measurement matches
ended in an elimination.** Every one hit the cap. See §The 20-minute cap could not be run.

## What I chose that you did not specify

| Choice | What I did | Why |
|---|---|---|
| **Match cap: 480 simulated seconds, not 1200** | Every measurement match ran to an 8-simulated-minute cap | Forced, not preferred — see §The 20-minute cap could not be run. This is the single largest departure from what you asked for |
| **`--jobs 4`, not 2** | Four concurrent Godot processes | Measured first: four matches complete in the same 105 wall-seconds two do, at 1.25 GB peak RSS against 3.9 GB available. The harness note's "three concurrent Godots swap" is stale; the pool default should be raised |
| **The readout is a MATERIAL MARGIN, not a win rate** | `army_energy_value + energy + 250 × structure_count`, slot 1 minus slot 0, at the cap | There were no wins to count. The 250 is the 2026-09-05 note's constant, kept so the two corpora are comparable, and it is still an estimate rather than a measurement |
| **The symmetry axis is a 180° POINT reflection** | `(x, z) → (−x, −z)`, keeping the x < 0 half | It is what the map's own `Map.mirror_secondary_axis = 2` declares, and it fits the authored entities 3× better than either pure flip (mean residual 3.3 world units against 10.3 and 11.0). See §Which diagonal |
| **Sensitivity uses `skirmish.tscn`, not the symmetric copy** | The original map throughout Part 2 | The start-position effect is not removed by the symmetric map, so switching would have bought nothing and broken comparability with the 2026-09-05 screen |
| **Archetypes** | The same five vectors, unchanged, from `tools/selfplay/results/archetypes.json` | Same-as-last-time is the point: a changed archetype would confound "the bot changed" with "the archetype changed" |
| **Both sides, always** | Every parameter arm and every round-robin cell played once from each start point | Mandatory here rather than tidy: the position advantage is ~10,000 material, larger than any effect being measured, and averaging the two sides cancels it exactly |

## The 20-minute cap could not be run, and this is the campaign's biggest limitation

You asked for the 20-minute cap. **It does not fit the machine this ran on.** Every shell
this campaign had was a fresh sandbox with a hard 180-second wall and no way to leave a
process running between calls — `nohup`, `setsid` and `disown` were all tested and all
reaped. A match runs at ~4.3 simulated seconds per wall second early and slower as entity
counts grow, so **a 480-second match takes 120–155 wall-seconds and a 1200-second match
takes over 400.** A 1200-second match therefore cannot complete inside any single call,
and a batch that never completes a match yields nothing at all — measured, at a cost of one
wasted 172-second call.

**What that costs the results, stated plainly.** At 480 seconds nothing is decided:
**0 eliminations in 144 measurement matches.** Every verdict in this note is a material
margin at minute 8, not a win. The 2026-09-05 note validated a margin-at-minute-10 proxy
against 20-minute outcomes 12 times out of 12, but it validated it on a bot with no income,
so that validation does not transfer and I am not leaning on it. **Everything here is a
statement about who is ahead at minute 8.** Re-running the round-robin at the full cap on a
machine that can hold a process for seven minutes is the first item in §What to run next.

## Part 1 — the start position

### The design, and why the confound had to be broken first

Slot index and start position are confounded in every match the harness has ever run:
`Skirmish._start_points` sorts the markers by name and hands the first to slot 0, so slot 0
is always the same corner — and deploy order, commander id and think order track the slot
index too. A corpus in which one slot wins more cannot say which of those produced it.

So the harness got one new option, `swap_start_points` — measurement infrastructure, not bot
behaviour. It exchanges the two markers' TRANSFORMS before the scenario enters the tree, so
node names, deploy order, commander ids and think order are all untouched and the only thing
that changes is which corner each slot deploys at. Validated before use: with the flag off,
commander 1 deploys at z ≈ +53 and commander 2 at z ≈ −55; with it on, they swap.

**Sixteen seeds, MEDIUM against MEDIUM with identical configuration, then the same sixteen
seeds again with the assignment exchanged.**

| | n | slot-1 material margin positive | 95% CI (Wilson) | binomial p vs 0.5 | mean margin |
|---|---|---|---|---|---|
| **A — authored assignment** | 16 | **16 / 16** | [0.806, 1.000] | **3.1 × 10⁻⁵** | **+9,632** |
| **B — assignment swapped** | 16 | 1 / 16 | [0.011, 0.283] | **5.2 × 10⁻⁴** | **−9,816** |

**The interval does not cover 0.5, so the skepticism about the sample size was right about
the sample size and wrong about the conclusion — the bias is real.** Decomposing the two
arms: the position is worth **+9,724** material and the slot index is worth **−92**, i.e.
nothing. The sign flipped on **15 of 16 paired seeds**. It shows up in the economy too:
the advantaged corner finishes with 4.25 extractors and 19.19 structures against 3.31 and
15.38.

### Which diagonal

The map's play rectangle is screen-aligned — its axes are s = x + z and t = x − z — so
"the diagonal" in play space is a world axis, and there are two candidate reflections plus
the 180° rotation that composes them. Measured over the authored geometry:

| Isometry | height residual (mean / max, in play) | tile cells differing | authored entities (mean / max residual) |
|---|---|---|---|
| **point `(x,z) → (−x,−z)`** | 0.107 / 1.500 | 0 / 12,641 | **3.26 / 26.5** |
| flip-Z `(x,z) → (x,−z)` | 0.103 / 1.500 | 0 / 12,641 | 10.26 / 44.0 |
| flip-X `(x,z) → (−x,z)` | 0.057 / 1.500 | 0 / 12,641 | 10.96 / 44.6 |

The point reflection is both the best fit for the authored entities and what the Map node
already declares (`mirror_primary_axis = HORIZONTAL`, `mirror_secondary_axis = VERTICAL`,
which `Map._mirror_map` reads as a 180° point reflection). It is the axis the symmetric copy
uses. Under it the two start points were **2.0 world units** off being each other's image —
`StartPoint1` at (−1, 57), `StartPoint1_mirror` at (−1, −57) where the reflection wants
(1, −57). That two-unit slip is the smallest asymmetry on the map and the least important
one.

### The symmetric copy

`scenes/scenarios/skirmish_symmetric.tscn` + `resources/terrain/mesh_plateau_terrain_symmetric.tres`,
generated by `tools/selfplay/results/make_symmetric_scenario.py`. **The authored
`skirmish.tscn` and its terrain resource are untouched.** The operation is the one
`Map.mirror_map` performs from the inspector — the x < 0 half of the corner heights and the
cell tile grid copied onto the x > 0 half through the reflection, every entity at x < 0 kept
and duplicated to its image, every entity at x > 0 dropped — with two departures the
inspector tool cannot make: the scene must hold exactly two start points, so the first is
kept and the second placed at its reflection; and `ShelterStructure3`, at (1.0, 0.0) and
therefore 1.0 from the reflection's only fixed point, is snapped onto the origin rather than
deleted. 16 entities kept, 16 reflections added, 15 dropped, 1 snapped — entity counts per
kind unchanged, closest pair of entities still 3.000 units, so the reflection introduced no
overlap.

**Verified numerically, by `tools/selfplay/results/verify_symmetry.py`, not by eye:**

| | original | symmetric copy |
|---|---|---|
| height residual under the point reflection, mean / max | 0.107 / 1.500 | **0.00000 / 0.000** |
| tile cells differing | 0 / 12,641 | **0 / 12,641** |
| authored entities, mean / max residual to a same-kind partner | 3.26 / 26.5 | **0.000 / 0.000** |
| the two start points | 2.000 apart from exact | **0.000** |

**One thing is deliberately NOT symmetric in the copy and does not affect measurement.** The
`TerrainSurface` MeshInstance3D still draws the authored `mesh_plateau_terrain_surface.res`.
Gameplay geometry does not come from it — `Map._ready` derives the collider from
`terrain_data.to_height_shape()`, `TerrainGrid` takes its blocked mask from
`terrain_data.blocked_mask()`, and `NavManager` builds the navmesh from the terrain grid — so
the mesh is cosmetic. It should be regenerated with `Map.generate_visual_mesh` before anyone
looks at this scene in the editor.

### The bias survives an exact symmetry, so the map was never the cause

Same 8 seeds, same MEDIUM mirror, on the symmetric copy:

| | n | slot-1 margin positive | binomial p | mean margin | sign flips vs A |
|---|---|---|---|---|---|
| **A — authored assignment** | 8 | **8 / 8** | 0.0078 | **+10,189** | — |
| **B — assignment swapped** | 8 | 0 / 8 | 0.0078 | **−9,470** | **8 / 8** |

**The advantage is the same size on a map with zero geometric residual, and it still follows
the position.** That is the result worth arguing with, because it rules out the obvious
explanation and points at a specific line of bot code.

### The mechanism: the build search prefers a world axis

`BotEconomy._find_build_spot` searches rings outward from the base and returns the FIRST
valid cell, scanning `for dx in range(-radius, radius + 1)` then `for dy` in the same order.
The first acceptable cell on a ring is therefore always the one furthest toward −X, then
−Z. **That is a preference in WORLD coordinates, and it does not mirror when the map does.**

Measured directly, on the symmetric map at tick 4500, as the mean offset of each commander's
owned structures from its own start point:

| commander | corner | owned entities | mean offset from own start |
|---|---|---|---|
| 1 | +Z (−1, 57) | 9 | dx **−4.96**, dz +4.14 |
| 2 | −Z (1, −57) | 11 | dx **−4.59**, dz −3.21 |

A true mirror image would put commander 2's mean at dx **+4.96**. Both build toward −X
instead, so on a point-symmetric map the two bases lay themselves out over different ground,
and the difference compounds: the first sample at which the two sides stop being exact mirror
images is **tick 60**, where the −Z commander already owns an extra `cl_infrastructure` under
construction. The two sides are never mirror images again.

**This is an attribution from an observation plus a code reading, not a controlled
experiment** — I did not change the scan, because changing bot behaviour mid-campaign is the
mistake this ordering exists to avoid. Randomising the ring scan's start angle, or ordering
candidates by distance-then-angle-away-from-the-enemy, is the fix to test, and testing it is
a 32-match re-run of exactly Part 1.

**What this means for everything else measured on this map.** Every A-versus-B comparison
inherits a ~10,000-material handicap that depends only on which corner a configuration
happens to sit in. It cancels when both sides are played, and this campaign plays both sides
everywhere — but a single-sided match on this map is uninterpretable, and roughly half the
2026-09-05 round-robin's cells were single-sided or split.

## Part 2 — the parameter space, re-measured

### The noise floor first, because it gates every number below

The harness is still not reproducible, and the failure has the same shape the 2026-09-05
note found. **Eight runs of one configuration** (seed 11, MEDIUM mirror, 480 s, same
process invocation):

| | |
|---|---|
| distinct trajectories | **2** |
| runs per branch | 7 / 1 |
| first differing sample | the **first sample after tick 0** (10 s) |
| trajectory distance between branches | **0.2657** |

**Bimodal, opening-tick, and unchanged in character.** The magnitude is comparable to the
0.2424 measured a day earlier on a different bot, which is consistent with one racing
decision in the opening rather than accumulated drift. `deterministic_navigation` was true
throughout and `run_match._force_single_threaded_avoidance` ran; neither removes it.

**And it confounds the single-match screen, demonstrably.** On seed 12,
`preserve_min_cost = 0`, `wave_abort_fraction = 0.0` and `wave_abort_fraction = 1.0` — three
different settings, two of them opposite ends of one field — all produced **the same
trajectory digest as each other** and a different one from the baseline. Three arms cannot
share one trajectory because of their parameters; they shared it because they landed on the
same branch. **A one-match "this parameter changed something" reading is worthless without
replication.** Bit-identity is still trustworthy in the other direction: a run identical to
the baseline changed nothing at all.

### The screen: all 8 previously-inert arms, plus the new knobs

One match each, slot 0 perturbed against an unchanged MEDIUM slot 1, seed 11, 480 s.
`diverge@` is the first sampled second whose state digest differs from the baseline match;
`trajdist` is the mean absolute difference in slot 0's army-energy series over the baseline's
own mean. Verdicts are the 2026-09-05 letters: **A** = bit-identical, **B** = wired but below
the 0.2657 noise floor, **C** = above it.

| Field | Value | trajdist | diverge@ | 2026-09-05 | **2026-09-06** |
|---|---|---|---|---|---|
| `army_commit_threshold` | 1 | 0.0000 | never | A | **A — survives** |
| `preserve_min_cost` | 0 | 0.0000 | never | A | **A — survives** |
| `wave_abort_fraction` | 1.0 | 0.0000 | never | A | **A — survives** |
| `defend_threat_radius` | 30.0 | 0.0000 | never | A | **A — survives** |
| `defend_threat_radius` | 3.0 | 0.0000 | never | A | **A — survives** |
| `preserve_min_cost` | −1 | 0.0063 | 260 s | A | **B — now reachable, barely** |
| `economy_reserve` | 1500 | 0.2408 | 10 s | **A** | **B — NOW ALIVE** |
| `demand_coverage_falloff` | 0.0 | 0.1044 | 270 s | **A** | **B — NOW ALIVE** |
| `economy_reserve` | 0 | 0.1028 | 220 s | C | B |
| `scout_unit_budget` | 4 | 0.1057 | 200 s | B (units only) | B |
| `build_concurrency` | 4 | 0.1096 | 10 s | C | B |
| `scout_unit_budget` | 0 | 0.2366 | 10 s | B (units only) | B |
| `income_structure_target` | 3 | 0.3317 | 70 s | *(new field)* | **C — LIVE** |
| `utility_unit_cap` | 6 | 0.3754 | 10 s | C | **C — LIVE** |
| `income_structure_target` | 0 | 0.3794 | 20 s | *(new field)* | **C — LIVE** |

### Which "inert" verdicts survive, replicated

The three arms that moved were re-run **four times each** and their trajectory digests
compared against **eight** baseline runs, so a branch flip cannot be mistaken for an effect:

| Arm | runs | distinct trajectories | runs landing on a BASELINE trajectory | reading |
|---|---|---|---|---|
| BASELINE | 8 | 2 | — | the branch flip, 7 / 1 |
| `economy_reserve = 1500` | 4 | 2 | **0 / 4** | **genuinely alive** |
| `demand_coverage_falloff = 0.0` | 4 | 2 | **0 / 4** | **genuinely alive** |
| `preserve_min_cost = −1` | 4 | 3 | 1 / 4 | **intermittent** — one run reproduced the baseline exactly |

And the five survivors were re-screened on a second seed. `army_commit_threshold` at both 1
and 12, and `defend_threat_radius = 3`, were **bit-identical to the seed-12 baseline as
well**. `preserve_min_cost = 0`, `wave_abort_fraction` at both ends and
`defend_threat_radius = 30` produced non-baseline trajectories on seed 12 that are the branch
flip described above, not effects — three of them share one digest.

**So, plainly: 3 of the 8 came alive, and the economy fix is why.** `economy_reserve = 1500`
was bit-identical to 600 because the bot never held a balance to reserve, exactly as
[bot-economy-diagnosis](bot-economy-diagnosis.md) predicted; it now binds from the first
sample. `demand_coverage_falloff` is the same story one rung up. **5 of 8 were not artifacts
of the broken economy**: the combat knobs — the commit threshold, the abort fraction, the
retreat price, the defend radius — are still not reachable from a MEDIUM mirror, and the
2026-09-05 reading of them stands.

### Effect on the objective, with intervals

Each arm played against unchanged MEDIUM from **both** start points on **two** seeds. The
objective is the 2026-09-05 shaped one (win 0.75–1.00, loss 0.00–0.25, undecided 0.25–0.75
on material margin), scored at a fixed 420 simulated seconds so a wall-capped match is still
comparable.

| Arm | n | mean | 95% CI | reading |
|---|---|---|---|---|
| `income_structure_target = 0` | 4 | 0.569 | [0.386, 0.752] | **spans 0.5** |
| `demand_coverage_falloff = 0.0` | 4 | 0.521 | [0.219, 0.822] | **spans 0.5** |
| `income_structure_target = 3` | 4 | 0.481 | [0.260, 0.703] | **spans 0.5** |
| `economy_reserve = 1500` | 4 | 0.439 | [0.193, 0.685] | **spans 0.5** |

**Every interval spans 0.5, so at this budget not one of these arms is distinguishable from
the unchanged bot.** That is the same verdict as 2026-09-05 and it should not be read as
"the parameter does nothing" — three of these four demonstrably change the simulation. They
change it by less than four matches can see.

**But there is a much cheaper estimator, and it is worth more than the extra matches.** The
variance in the table above is dominated by the start-position advantage, which sits inside
each arm as a ±0.15 swing between its two sides. Averaging the two sides of a seed BEFORE the
statistics cancels it:

| Arm | seed-11 pair | seed-12 pair | side-paired mean |
|---|---|---|---|
| `demand_coverage_falloff = 0.0` | 0.522 | 0.520 | **0.521 ± 0.001** |
| `income_structure_target = 3` | 0.492 | 0.471 | 0.481 ± 0.011 |
| `income_structure_target = 0` | 0.619 | 0.519 | 0.569 ± 0.050 |
| `economy_reserve = 1500` | 0.390 | 0.488 | 0.439 ± 0.049 |

Two seed-pairs is far too few to trust a standard deviation, so read this as a lead rather
than a result — but `demand_coverage_falloff` reproducing to ±0.001 across independent seeds,
against a ±0.19 spread in the unpaired data, says the side-paired estimator is worth
measuring properly. If it holds, an arm needs **6–10 seed-pairs (12–20 matches)** where the
unpaired design above needs **51–648**.

## Part 3 — the round-robin

Five archetypes, unchanged vectors, every pair from both start points on seeds 11 and 12:
**40 matches, 4 per cell.** Scored at a fixed 420 simulated seconds. Cell value is the row's
mean objective against the column; above 0.5 means the row is ahead.

|  | ECONOMIST | MEDIUM | RUSHER | SKIRMISH | TURTLE | mean |
|---|---|---|---|---|---|---|
| **ECONOMIST** | — | 0.660 | 0.717 | 0.521 | 0.642 | **0.635** |
| **SKIRMISH** | 0.479 | 0.552 | 0.710 | — | 0.574 | **0.579** |
| **MEDIUM** | 0.340 | — | 0.637 | 0.448 | 0.516 | 0.485 |
| **TURTLE** | 0.358 | 0.484 | 0.667 | 0.426 | — | 0.484 |
| **RUSHER** | 0.283 | 0.363 | — | 0.290 | 0.333 | **0.317** |

- **Bradley-Terry:** ECONOMIST +0.459, SKIRMISH +0.264, MEDIUM −0.045, TURTLE −0.053,
  RUSHER −0.625. Residual SS 0.0098 against total SS 0.3848 — **R² = 0.975**, a cyclic
  component of 2.5%, which at four matches per cell is indistinguishable from noise. The
  largest residual is ECONOMIST vs MEDIUM at +0.036.
- **No cycle exists.** All ten 3-cycles searched in both orientations; none is closed. The
  result you were hoping for is still not here, and a working economy did not produce it.
- **What DID change from 2026-09-05.** The ordering was ECONOMIST > SKIRMISH > RUSHER >
  TURTLE > MEDIUM. It is now ECONOMIST > SKIRMISH > MEDIUM ≈ TURTLE > **RUSHER**. **RUSHER
  fell from third to last and MEDIUM climbed off the bottom.** That is the fix showing up
  where you would expect it: RUSHER's whole identity is `economy_reserve = 0`, and a reserve
  of zero was free when nobody had an income and is now a real handicap. The shipped MEDIUM
  tier is mid-table rather than worst.
- **ECONOMIST's margin narrowed against SKIRMISH** — 0.892 on the old matrix, 0.521 here, a
  coin flip. That is the one pairing where the greedy-economy dominance is no longer clean.

**Power, plainly.** Four matches per cell, two per side. **No individual cell is
distinguishable from a coin flip**; the two-sided p-value floor at n = 4 is 0.125. What the
matrix carries is the side-controlled signal: four cells produced the same winner from both
start points on both seeds — **RUSHER loses to MEDIUM, ECONOMIST, SKIRMISH and TURTLE, all
four side-controlled.** RUSHER being last is the one claim in this matrix I would defend.
Every other cell splits by side, which is the start-position advantage showing through.

## Bugs and anomalies

**1. The build-spot ring scan has a world-axis preference.** §The mechanism. It is worth
~10,000 material by minute 8 between two otherwise identical commanders on an exactly
symmetric map. **This is the highest-value bug in this note** and it corrupts every
uncontrolled A-versus-B comparison the harness produces.

**2. Nothing ever ends.** **0 eliminations in 144 matches.** With both economies working,
both sides rebuild faster than either can flatten the other inside eight simulated minutes.
The 2026-09-05 corpus's 24 decisive results out of 85 came from bots that could not replace
losses. This is not obviously a bug — it may be a fair report that eight minutes is too
short — but it means the harness currently produces no win/loss signal at all, and the
training objective is entirely carried by the shaping constant.

**3. Idle units got WORSE, not better.** Peak idle per slot-trajectory: **median 7, maximum
25**, against the 2026-09-05 median 5 / maximum 18. A richer bot builds more units it has no
standing behaviour for. [bot-roadmap](bot-roadmap.md) §gap 2 is now costing more than it was.

**4. DEFEND is nearly dead, and flaps when it is not.** Of 14,096 posture samples: MASS
6,560, ATTACK 7,374, **DEFEND 162 (1.1%)**. And 49 of the 53 posture A→B→A reversals within
three transitions are **ATTACK ↔ DEFEND**. So the posture is entered rarely and, when
entered, is unstable. `defend_threat_radius` being bit-identical at 3.0 and 30.0 and DEFEND
being 1.1% of samples are plausibly the same fact: the branch is barely reachable.

**5. The economy fix holds, and holds well.** Banked energy is exactly zero in **0.3%** of
slot-samples (was 71.1%), and **0 of 288 slot-trajectories** finished owning zero extractors
(was 145 of 170). Median final structure count 16, minimum 7; **no slot-trajectory ended
alive with zero structures**, so the elimination-rule distortion that dominated the last
corpus is gone.

**6. Scout coverage is still capped low.** Peak observed fraction: min 0.09, median 0.45,
max 0.61. Better than the old 0.07 / 0.42 / 0.64 at the top end but the same shape — the
0–4 ramp did not open the map up.

**7. ECONOMIST is still a performance hazard.** 4 of 40 round-robin matches hit the wall
cap short of 480 simulated seconds, and all four involved ECONOMIST. Its matches run at
89–100 ticks per wall second against a corpus median of 108.

**8. The `--jobs 2` default is leaving half the machine idle.** Four concurrent matches
complete in the same wall time two do, at 1.25 GB peak. `run_batch.py`'s docstring and
[selfplay-harness](selfplay-harness.md) both still say three Godots swap; they should be
re-measured and the default raised.

## What to run next

Ordered by value per match, with costs at the measured throughput (~4 matches per 150
wall-seconds at `--jobs 4`, 480 simulated seconds each).

1. **Fix the build-spot scan, then re-run Part 1. ~32 matches (0.35 core-hours).**
   Randomise `BotEconomy._find_build_spot`'s ring traversal from the seeded generator, or
   order candidates by distance then by angle away from the enemy, and re-run the 16-seed
   mirror plus the 16-seed swap. If the margin collapses toward zero, the largest
   confounder in the whole instrument is gone and every comparison after it gets cheaper.
   **Do this before any further search.**

2. **Get decisive matches back. ~20 matches (0.5 core-hours), on a machine that can hold a
   process for seven minutes.** Run the MEDIUM mirror at the full 1200-second cap and find
   out whether the minute-8 margin predicts the 20-minute verdict on a bot with an economy.
   Until that is known, every objective in this note rests on the `250 × structures`
   shaping constant.

3. **The side-paired estimator, properly. ~40 matches (0.45 core-hours).** Ten seed-pairs
   for each of four arms. If the ±0.001 reproducibility seen at two pairs survives at ten,
   the cost of a usable sensitivity measurement drops by a factor of 20 and a real search
   becomes affordable for the first time.

4. **Find the opening coin flip. ~20 matches (0.25 core-hours).** Still the 2026-09-05
   recommendation and still not done. Run one config 20 times with `state_dump_path` and
   bisect the first divergent tick. The branch flip is now demonstrated to produce false
   positives in the screen (§the noise floor), so it is no longer only a precision problem.

5. **Make the combat knobs reachable, then re-run the round-robin. ~40 matches
   (0.45 core-hours) after the change.** Five of the eight dead arms are the aggression
   side of the space, and a space where only the economy moves has no mechanism to produce
   the intransitivity you are after. The round-robin is worth repeating the moment
   `attack_value_ratio`, `army_commit_threshold` and `wave_abort_fraction` can change a
   match.

6. **The round-robin at cells that can reject a coin flip. ~120 matches (1.4 core-hours).**
   Six archetypes at 10 matches per cell over two seeds, both sides. Worth it after 1 and
   5, not before — cells at n = 4 cannot see a cycle even if one exists.
