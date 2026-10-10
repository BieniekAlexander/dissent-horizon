---
title: Bot performance
type: system-note
---

# Bot performance

*Design note for [Dissent Horizon](../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

**MEASURED (2026-09-25), native macOS (M3 Pro), headless.** Per-physics-tick cost of
`scenes/scenarios/skirmish.tscn` with every slot forced to a MEDIUM bot, against the 30
physics-FPS budget of **33.3 ms/tick**. 7,107 ticks (3.9 simulated minutes) of one match, plus a
phase-by-phase breakdown of a navmesh rebuild. The 2026-09-05 measurement this replaces was
taken on a 160×160 map at 55–70 commandables; the skirmish map is now **261×261** (2.66× the
area) and the match reaches **184 commandables / 83 units by minute 4**, so its verdict — ten
times the headroom needed — no longer holds.

## The verdict

**The game does not fit the budget, in three separate ways.**

1. **Navmesh rebuilds freeze the game for ~800 ms**, once per `TerrainGrid.cells_changed` —
   every structure placed AND every structure destroyed. 21 in the first 4 minutes.
   **Fixed 2026-09-26: now 3–4 ms** ([incremental-navmesh](../terrain-and-navigation/incremental-navmesh.md)).
2. **The bot think pass spikes to 40–185 ms every 20 ticks** (twice a second), and grows with
   army size. Nearly all of it is `BotScout`. This is a rhythmic stutter, not a rare hitch.
3. **The steady state overruns once armies form.** Tick p50 climbs from 12.7 ms to 29.5 ms by
   minute 4 (83 units), with p95 at 95 ms; 16.5% of all ticks exceed the budget.

**Caveat that applies to every number here:** headless uses the dummy renderer, so rendering
is not included, and there is no `RTSController`, HUD or minimap. A windowed session pays all of
those on top.

## What a tick costs

Ticks 300+ (boot excluded). All values ms.

| | p50 | p90 | p95 | p99 | max |
|---|---|---|---|---|---|
| **full tick** | 22.36 | 39.81 | 59.46 | 119.93 | 878.55 |
| script phase | 19.33 | 35.96 | 53.87 | 108.43 | 330.85 |
| fog, both commanders | 5.87 | 7.03 | 7.41 | 8.51 | 47.75 |
| engine (tick − script) | 2.83 | — | 3.97 | 6.59 | 857.46 |

**Over 33.3 ms: 1,172 of 7,107 ticks (16.5%).** Of those, 290 are bot think ticks, 34 are
navmesh rebuilds, and 848 are ordinary ticks where the entity layer alone overran.

By simulated minute:

| min | units | pieces | tick p50 | tick p95 | fog | entity layer p50 | think-tick bot p50 / max | over budget |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 0–1 | 28 | 120 | 12.74 | 27.27 | 3.49 | 7.08 | 9.9 / 111.5 | 72 |
| 1–2 | 59 | 154 | 20.23 | 44.77 | 5.28 | 11.57 | 27.0 / 173.1 | 154 |
| 2–3 | 61 | 161 | 24.26 | 59.91 | 6.28 | 14.36 | 40.7 / 184.8 | 268 |
| 3–4 | 83 | 184 | 29.49 | 95.31 | 6.90 | 18.25 | 42.2 / 141.6 | 678 |

The think pass, both bots summed, per think tick:

| Stage | p50 | p95 | max |
|---|---|---|---|
| **`BotScout.tick`** | **26.87** | **75.02** | **178.33** |
| `BotTargeting.tick` | 1.27 | 3.29 | 24.34 |
| `BotProduction.tick` | 1.21 | 2.51 | 4.33 |
| `BotSanction.tick` | 0.96 | 1.50 | 2.92 |
| `BotMilitary.tick` | 0.70 | 3.44 | 6.05 |
| `BotOpportunist.tick` | 0.18 | 4.23 | 24.58 |
| `BotEconomy.tick` | 0.14 | 1.03 | **154.86** |
| `BotMomentum.tick` | 0.07 | 0.11 | 0.83 |
| `BotKamikaze.tick` | 0.00 | 0.03 | 0.08 |

**Every think tick carries both bots.** All 370 think ticks in the run had exactly two thinks:
`BotBrain._ticks_since_think` starts at 0 for every brain, so the bots' cycles are in phase and
their spikes stack.

## A navmesh rebuild, phase by phase

*The monolithic build as it was before the incremental navmesh; kept as the baseline.*

`NavManager._rebuild_navmesh` on the 261×261 grid (30,791 passable cells), five repetitions,
mean. It builds four meshes: the un-eroded base and one per `NavAgentClass.Size`.

| Phase | ms | Notes |
|---|---|---|
| `_recompute_clearance` | 7.2 | paid lazily by the first reader after `cells_changed` |
| `_recompute_distance` | 21.9 | same |
| `_recompute_components` | 10.9 | same; read by bot placement, not by the navmesh |
| `get_navigable_cells`, per mesh | 82 / 83 / 107 / 114 | **82 ms even for `rings=0, admit_k=1`** |
| `_build_mesh`, per mesh (includes the above) | 151 / 180 / 204 / 200 | |
| handing meshes to the server | < 0.2 | |
| `NavigationServer3D.map_force_update` | ~20 | measured with the map async; it is synchronous now ([navigation-and-pathing](../terrain-and-navigation/navigation-and-pathing.md) §Navigation is synchronous, for replay) |
| **`_rebuild_navmesh`, total** | **726–773** | |
| **wall time of the frame after one `set_blocked`** | **800** | the real player-facing cost |

**All but ~20 ms of this is our GDScript, not the engine.** `get_navigable_cells` costs 82 ms
for the trivial base mesh, where no erosion runs at all, so the cost is per-cell call overhead:
a call to `is_navigable_for` for each of 68k cells, each with its own bounds check,
`_ensure_fields` and Dictionary insert. `_build_mesh` then spends a similar amount allocating a
4-element `Array[Vector2i]` and a `PackedInt32Array` for each cell, calling `add_polygon` once
per cell, and keying vertices in a `Dictionary` by `Vector2i`.

**The cost scales with map area, not with what changed.** A one-cell change pays for all 68k
cells, four times over. That was 240 ms on the 160×160 map, is 750 ms at 261×261, and a
larger generated map pays more again.

## Re-measured 2026-09-26

Same skirmish, five simulated minutes, headless with `--fixed-fps 30` (so a tick's wall time is
its real cost), after the fixes in the plan below. All values ms per tick.

| | before path straightening fix | after |
|---|---|---|
| full tick, p50 / p95 / p99 | 10.0 / 25.6 / 35.2 | 9.6 / 15.8 / 24.8 |
| unit and structure scripts, p50 | 6.3 | 5.8 |
| fog, both commanders, p50 | 1.0 | 1.2 |
| bots, mean | 0.3 | 0.4 |
| engine (tick − script), p50 | 1.9 | 2.0 |
| ticks over 33.3 ms | 118 of 8,701 (1.4%) | 45 of 8,701 (0.5%) |

The two matches differ (55 vs 79 units at peak), so compare shares, not absolutes. What is left
of the unit and structure script time, per the per-function timings: the command logic itself
(~1.3 ms), synchronous path queries (~0.7 ms, and the spikes of item 10), path straightening
(~0.7 ms), then velocity callbacks, avoidance priority and height snapping at 0.1–0.3 ms each.

## Native ports, measured 2026-10-09

The same skirmish (every slot a MEDIUM bot), 9,000 ticks headless with `--fixed-fps 30`, in a
2-vCPU cloud container — slower than the M3 Pro above, so compare the two columns with each
other, not with the earlier sections. Headless spectator play now carries the HUD's minimap,
which is where most of the time had gone: a per-pixel fog blend of the whole minimap every
frame, and a whole-map layer rebuild on every structure placed or lost.

A script-profiler run of one match picked the three loops ported to C++
([authoring/native-code](../authoring/native-code.md)): the minimap draw and layer rebuild, the
terrain grid's cell queries, and fog sight stamping. Ticks 300+, ms.

| | GDScript | native |
|---|---|---|
| full tick, mean / p50 / p95 / p99 | 43.4 / 40.3 / 62.2 / 85.9 | 16.2 / 14.3 / 31.5 / 44.3 |
| script phase, mean | 14.6 | 11.5 |
| fog, both commanders, mean | 1.5 | 0.7 |
| ticks over 33.3 ms | 7,235 of 8,700 (83%) | 336 of 8,700 (3.9%) |
| ticks over 150 ms | 29 | 3 |

Both runs reached the same unit and piece counts minute by minute, so the ports changed nothing
the simulation decides. The 26 stalls that went were the minimap rebuild. **TODO — the three
left are shelters producing residents** (every ~10 s early on, ~300–370 ms each): spawn-point
search projects each candidate onto the navmesh with `NavigationServer3D.map_get_closest_point`,
2–3 ms a call on this map and already native. Answering "nearest passable cell" from the terrain
grid instead would remove them; not built.

What remains of a tick, by function: the per-actor order, command and movement logic (~11 ms at
~100 pieces), the bot think pass (~2 ms mean), the engine (~3–5 ms), and per-frame visual work
(`StatusVisuals`, ~2 ms) that runs even headless.

## The plan, ranked by payoff

The fixes live in the notes that own each system. This is the index and the order.

| # | What | Status | Expected | Owner |
|---|---|---|---|---|
| 1 | Incremental navmesh: staggered K=16 chunks, packed build, local fields | **Built 2026-09-26** | ~800 ms freeze → 3–4 ms, measured | [terrain-and-navigation/incremental-navmesh](../terrain-and-navigation/incremental-navmesh.md) |
| 2 | Put the bots out of phase | **Built 2026-09-26**, by the shared scheduler | both bots' work never stacks on one tick | [think-scheduling](think-scheduling.md) |
| 3 | `BotScout` visits only the points in each unit's vision window | **Built 2026-09-26** | scout sight 27 ms → ~0.3 ms per run | [think-scheduling](think-scheduling.md) |
| 4 | Budgeted think scheduler | **Built 2026-09-26**; the budget is provisional (deferred 1.38) | bot time p99 63 → 2.8 ms, ticks over 33 ms 200 → 2 | [think-scheduling](think-scheduling.md) |
| 5 | Staggered aggro re-acquire + allegiance in the query | Allegiance **built 2026-09-26**; the stagger is REJECTED (Alex, 2026-09-26) | aggro now 0.27 ms/tick, measured | [combat/scan-and-vision-cost](../combat/scan-and-vision-cost.md) |
| 6 | Reference-counted, diffed fog; upload only the viewed fog | **Built 2026-09-26** at one pixel per cell; coarser fog is TODO (deferred 1.40) | fog 7.5 → 1.0 ms p50, measured | [combat/scan-and-vision-cost](../combat/scan-and-vision-cost.md) |
| 7 | `BotEconomy`'s build-spot outlier | **Built 2026-09-26**: the search is resumable | 115 ms spike → spread across ticks | [think-scheduling](think-scheduling.md) |
| 8 | Minimap layer rebuilt on every `cells_changed` | **Built 2026-10-09**, by the native ports rather than a dirty rect | 300–450 ms stall per placement → gone, measured | [authoring/native-code](../authoring/native-code.md) |
| 9 | Path straightening bounded by a reach, crossed-cell line test | **Built 2026-09-26** | 3.6 → 0.7 ms/tick, measured; its 6-tick spikes gone | [terrain-and-navigation/navigation-and-pathing](../terrain-and-navigation/navigation-and-pathing.md) §What path straightening costs |
| 10 | Every moving agent re-plans in one tick after a navmesh change | **Built 2026-09-27**: only paths the change reaches re-plan | worst tick after a change, median 35.6 → 3.8 ms, measured | [terrain-and-navigation/navigation-and-pathing](../terrain-and-navigation/navigation-and-pathing.md) §Re-planning after a navmesh change |
| 11 | A chasing unit re-plans whenever its target moves | **Built 2026-09-27** while the quarry is in straight-line reach; the rest is backlog | path queries −70%, measured | [terrain-and-navigation/navigation-and-pathing](../terrain-and-navigation/navigation-and-pathing.md) §A path is the straight line whenever the unit can walk it |

Items 2, 3, 4 and 7 were built together on 2026-09-26; the rule they share is written up in
[think-scheduling](think-scheduling.md). Item 7's cause, found then: checking the ranked
build-spot candidates one by one, each through the full placement rules, on a crowded base.

**The rule the bot needs, beyond the individual fixes:** a manager's cost must be
proportional to what it looks at, never to the map. Both big sweeps so far (`BotScout`, and
before it the `BotEconomy` flood fill) scaled with map area. That was invisible at 160×160 and
now dominates.

**REJECTED (2026-09-25, for now) — a performance gate in the simulation harness** that fails
a run over a think-time budget.

## Re-measured 2026-10-10: ten random maps, a forced long game, and the per-job profile

Alex reported a game that crawled at its end. Three instruments, all headless, `--fixed-fps 30`,
HARD Colonial mirrors:

1. **Ten `run_match` games on ten random generated maps** (seeds from `random.seed(20261010)`),
   20-minute cap, 30 s samples, with the new per-job profile: `BotScheduler` now sums every
   job's microseconds, work units and runs (`BotJob.total_usec` and friends), and a sample
   carries them per slot (`jobs`) beside `wall_seconds`, so two samples give the wall cost per
   tick of the window between and each job's share of it. Nine ended by elimination inside
   seven minutes at 60–94 ticks per wall second; one (seed 43174) ran eighteen minutes at an
   average of 23, that is 43 ms a tick.
2. **One forced long game** on the skirmish map, both slots `may_attack: false`, so bases and
   armies grow unopposed for ten minutes (54 structures and 113 units at the end).
3. **The per-tick probe** (`tools/_perf_probe_tmp.tscn`, fifteen simulated minutes on the
   skirmish map, bots playing normally) for the script / fog / brain split.

**What a tick costs now, by simulated minute** (ten random maps, p50 of 30 s windows):

| minute | 0 | 2 | 4 | 6 | 8 | 10 | 12 | 14 | 16 | 18 |
|---|---|---|---|---|---|---|---|---|---|---|
| ms per tick | 4.8 | 12.1 | 19.1 | 22.9 | ~70 | ~70 | ~69 | ~40 | ~43 | ~60 |
| bot jobs, both bots, ms per tick | 0.7 | 2.4 | 4.3 | 6.0 | 6.9 | 4.1 | 6.6 | 5.7 | 6.8 | 4.8 |

Past minute seven the columns are seed 43174 alone. **Two different late games, two different
costs:**

- **A fought late game** (seed 43174, 50–90 pieces, armies in contact): 70–85 ms a tick from
  minute eight, of which the bot jobs are 5–8 ms. The other sixty-plus milliseconds are the
  entity layer — units in contact, pathing and avoidance — not a bot decision. The per-tick
  probe on the skirmish map, where the armies stayed at 60–75 units and 48 structures, showed
  none of it: 10–12 ms a tick throughout, script 7–9, brain 2–5, fog 0.4. TODO: the probe
  cannot boot a generated map (`run_match._apply_generated_map` is what does), so the fought
  late game on a large generated map is measured only as a total. The backlog's first item
  (chasers re-planning out of straight-line reach) is the standing suspect.
- **A built-up late game** (the forced long game): once a base passes about fifty structures
  the ECONOMY job alone costs 60–130 ms a tick and the bot jobs are three quarters of a frame
  of 80–155 ms. This is bot work, it is one job, and it is the shape Alex described: a long
  game, a big base, a bot that thinks slower every minute. §The economy job's late-game cost,
  below.

**The work-unit calibration is wrong for most jobs**, which is why the scheduler's 2000-unit
budget (≈2 ms) did not bound the bot at 5–8 ms a tick. Microseconds per claimed work unit over
the ten maps (1.0 is honest):

| job | µs per unit | ms per tick at minute 12 | note |
|---|---|---|---|
| `escort` | 199 | 1.0–2.0 | the first build of `Bot.relations()` scanned every pair of pieces each combat period; fixed the same day (providers only) |
| `posture` | 113 | 0.15 | 2 ms a run for 20 units claimed |
| `research` | 23 | 0.00 | negligible total |
| `economy` | 18 | 1–4 (fought), 60–130 (built up) | its own counters do not see the rungs below |
| `opportunist` | 9 | 0.02 | |
| `production` | 8.6 | 0.5–1.4 | |
| `military` | 7.1 | 1–2 | |
| `fields` | 1.6 | 0.6–0.9 | calibrated |
| `scout`, `scout_sight`, `targeting`, `sanction`, `abilities`, `deployment`, `momentum`, `preservation` | 0.4–1.9 | < 0.3 each | calibrated |

The rule from §The plan still holds and was broken twice: a manager's cost must be
proportional to what it looks at. The escort read every piece against every piece; the economy
reads the map.

### The economy job's late-game cost

Found 2026-10-10 with checkpoint timers on the economy ladder and wrappers on the `Bot` reads
it makes, in the forced long game (both bots `may_attack: false`, so the base grows to fifty
structures by minute six). Cumulative wall time of the heaviest sections, both bots, at
simulated minutes two, four and six:

| section | calls / ms at 2 min | at 4 min | at 6 min |
|---|---|---|---|
| `Bot.home_centroid` | 16,037 / 2,132 | 39,283 / 8,503 | 91,958 / 28,315 |
| `Bot.enemy_demand_map` | — | 5,273 / 4,964 | 6,768 / 17,432 |
| `Bot.purchase_values_per_energy` | 3,174 / 1,680 | 5,199 / 5,571 | 6,586 / 14,837 |
| `Bot.believed_enemy_composition_clocked` | — | 3,321 / 3,668 | 4,501 / 11,991 |
| `BotEconomy._propose_savings` | 953 / 1,942 | 1,518 / 7,664 | 1,978 / 23,177 |
| `Bot.relations` (escort, first build) | — | — | 1,354 / 3,705 |

So between minutes four and six the economy spent twenty seconds of a two-minute window in
`home_centroid()` alone — a quarter of a tick, every tick. Three things compounded:

1. **`home_centroid()` re-clusters the bot's structures on every call** (`bases()`), and the
   threat clock asked for it ONCE PER BELIEVED ENEMY: `_clocked` read the home position inside
   the loops of `enemy_demand_map` and `believed_enemy_composition_clocked`. Fifty structures,
   sixty believed enemies, and the clustering ran sixty times per demand map.
2. **The demand map and the clocked composition were recomputed on every ask**, and the
   economy asks six to eight times a think: `_propose_savings` (which runs `_best_tech` and
   `producer_values`), `_production_structure_to_build`, `_tech_candidates_scored`, the defence
   rung, and production's own pass. Each recomputation also pays an effectiveness evaluation
   per (believed type × own unit), which is the term that grows with the army.
3. **The escort's relation read scanned every pair of pieces** each combat period (§above).

**The fix (same day):** `home_centroid()`, `enemy_demand_map()` and
`believed_enemy_composition_clocked()` are MEMOISED FOR ONE TICK on `Bot` (keyed by the
scenario's tick; a bot off a scenario recomputes, as a test expects), `_clocked` takes the home
position as an argument so the loops read it once, and `Bot.relations()` reads providers only.
Memoisation is justified here by §1.1's rule: the recomputation is a clustering plus an
army-sized evaluation, and nothing the three read changes within a tick except by the bot's own
hand, one cell at most.

**After the fix, the same forced long game, eight simulated minutes** (59 units and a
fifty-structure base by minute six): tick p50 4.0 → 16.4 ms across the game, the bot jobs
14–18% of it throughout, and the economy job 0.2–0.9 ms a tick where it had been 60–130.
Per-job microseconds per claimed unit: economy 8.4 (was 18–80), escort 4.4 (was 199),
production 1.4, military 1.6, fields 1.6, posture 83, opportunist 4.8, research 20.

**Recalibrated the same day**, so the budget means what it says: `BotBrain.POSTURE_WORK_UNITS`
20 → 1700 (1.6–2.1 ms a run measured), `BotEscort` 8/4 → 35/18 per squad and piece,
`BotOpportunist` 3/12 → 15/60 per opportunity and gather. TODO: the economy's own counters
still claim an eighth of what the job costs; they count ranked spots and sweeps and not the
valuations each rung asks for. A per-rung fixed cost measured as above is the honest repair,
and the think-scheduling note's debug-build tripwire (§Backlog) is what would have caught all of
this a week earlier.

## Backlog: optimizations not built

Every candidate turned up by the 2026-09-25/27 performance work and not built, in rough order
of expected payoff. Each is a `TODO` in the note that owns it, with the research; this list is
the index. None is needed today — the skirmish runs 0.2–0.5% of ticks over budget — so pick
from here when a measurement says so.

| What | Expected payoff | Owner |
|---|---|---|
| Chasers out of straight-line reach: distance-relative re-plan threshold (or a staggered timer) | most of the remaining path queries in a fight | [navigation-and-pathing](../terrain-and-navigation/navigation-and-pathing.md) §A path is the straight line |
| Region relabel local to a change | the bots' last 10–13 ms single-tick cost | [incremental-navmesh](../terrain-and-navigation/incremental-navmesh.md) |
| Path straightening reads a cached per-class navigability grid | ~half of its 0.7 ms/tick | [navigation-and-pathing](../terrain-and-navigation/navigation-and-pathing.md) §What path straightening costs |
| Fog: edge-only re-stamp for a small move (0 A.D.'s "mostly-overlapping circles") | the part of fog that grows with moving units | [combat/scan-and-vision-cost](../combat/scan-and-vision-cost.md) §The fog of war |
| `BotScout` reads the bot's own fog counts instead of raycasting | the scout's sight sweep; a behaviour change | same, TODO — follow-on |
| Retaliation's vision query filtered by side | correctness in crowds more than cost | [combat/target-acquisition](../combat/target-acquisition.md) |
| Per-side spatial hash replacing Godot's shape queries | only if aggro grows costly again (0.27 ms/tick now) | [combat/scan-and-vision-cost](../combat/scan-and-vision-cost.md) §The aggro scan |
| Incremental path search (Moving Target D* Lite) | only with our own A* | [navigation-and-pathing](../terrain-and-navigation/navigation-and-pathing.md) |
| A debug-build wall-clock tripwire for bot work-unit weights | catches drift, saves nothing | [think-scheduling](think-scheduling.md) |
| Simulation below 30 Hz with interpolated rendering (deferred 1.41) | every per-tick cost by a third | [combat/scan-and-vision-cost](../combat/scan-and-vision-cost.md) §Beyond both |

## Method

`tools/_perf_probe_tmp.tscn` boots a scenario with **every player slot forced to a bot** (a
spectator session, so nothing waits on input) and writes one CSV row per physics tick:

```
godot --headless --fixed-fps 30 --path . res://tools/_perf_probe_tmp.tscn -- \
  --out=/abs/path.csv --ticks=7200
```

| What | How |
|---|---|
| **Fast-forward** | `--fixed-fps 30` decouples the loop from the wall clock with `delta` held at 1/30 s. `Engine.time_scale` alone is NOT usable: in 4.7 it scales delta, it does not add steps. Paired with the engine tick rate it is — that is debug playback speed (ux/ui/debug-mode.md §Playback speed) — but the harness has no need of it |
| **Full tick cost** | wall-clock delta between consecutive ticks, minus the probe's own sampling time |
| **Script share** | hook nodes at `process_physics_priority` −10000 and +10000 bracket the `_physics_process` phase |
| **Bot share, per stage** | each `BotBrain`'s own `_physics_process` is disabled and replayed from a hook at priority 90, timing each manager in `think()`'s order. **The replay duplicates `think()`'s manager list, so update it when `think()` changes** |
| **Fog share** | the same take-over, at priority 1 |

The rebuild breakdown came from a throwaway scene kept outside `res://`, which the editor
never sees. It instantiates the same spectator skirmish, waits for `NavManager.is_ready()`,
disables the brains and times each phase of `_rebuild_navmesh` directly. It then calls
`set_blocked` on one cell and records the wall time of the following frames. It was not
committed; the table above is its whole output.

**One trap:** `Performance.TIME_PHYSICS_PROCESS` and `TIME_PROCESS` are not per-tick values.
Godot refreshes them once per second and reports that second's maximum. Every per-tick figure
here is measured directly.

## Limits of this measurement

- Headless, dummy renderer: **no rendering cost**, and no HUD, `RTSController` or minimap.
- The machine was not idle (load average ~7 on 11 cores, with the Godot editor open).
  GDScript runs on one core, so contention adds noise rather than a systematic offset, but
  single ticks can pick up extra latency from it.
- One map (skirmish, 261×261) and one bot difficulty (MEDIUM). Items 1, 3, 6 and 8 of the
  plan all scale with map area, so a larger map is worse on every one of them.
- The run was stopped at 3.9 simulated minutes rather than a full match; the population was
  still rising, so later minutes will be heavier than the last row of the table.
