---
title: Navigation and pathing
type: system-note
---

# Navigation and pathing

*Design note for [Dissent Horizon](../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

## `NavManager` (`scripts/maps/terrain/nav_manager.gd`)


Builds the `NavigationMesh` directly from `HeightMapShape3D` data (not from baked 3D geometry), with shared vertices across adjacent cells. Rebuilds are debounced with `call_deferred`. The navmesh excludes building-occupied, steep, and impassable-typed cells automatically.

**Do not change the navmesh building approach** — it avoids Godot's slow geometry-bake path and correctly encodes terrain heights.

#### Navigation is synchronous, for replay

`project.godot` turns off async iteration for navigation maps and regions
(`navigation/world/map_use_async_iterations`, `…/region_use_async_iterations`), so a navmesh
change lands on the tick that asked for it rather than whenever a worker thread finishes. That
is what makes a match reproducible from its seed and inputs: an async region once deployed the
opening force on tick 1 in some runs and tick 2 in others, and every decision after that ran a
tick out of step ([selfplay-harness](../ai/selfplay-harness.md) §Determinism). The setting reaches
the chunk regions `NavManager` makes by RID as well as scene nodes, which
`tests/test_NavChunks.gd` checks. Measured before switching: no frame-time cost (headless,
seed-1 match, 9,000 ticks — mean 5.3 ms sync vs 6.1 ms async, p99 ≈ 11 ms both).

RVO avoidance is single-threaded for the same reason
(`navigation/avoidance/thread_model/avoidance_use_multiple_threads = false`): on worker threads,
one seed played a different match in every process ([selfplay-harness](../ai/selfplay-harness.md)
§Determinism).

#### Do NOT merge cells into larger polygons — it was tried and reverted

One quad per cell means Godot's polygon A* picks one cell corridor out of many equal-cost ones, and the funnel can only pull the string taut *inside* the corridor it was handed — so a shallow diagonal comes back as "run along +x for a while, then cut". Merging cells into large convex polygons is the obvious fix and on an empty flat square it works perfectly (6.8% worst-case excess → 0.0%). **It cannot be represented in this engine**, and the failure is silent:

- Godot links navigation polygons by **exactly-matching edges**. A merged rectangle's long side against several smaller neighbours is a T-junction, and those polygons simply do not connect.
- Subdividing each polygon's perimeter at every cell corner fixes the T-junctions and **breaks point containment**. NavigationServer treats a polygon carrying collinear perimeter vertices as covering only its boundary: every interior point of a 3×32 subdivided rectangle fails to resolve onto it, while the same rectangle as a plain 4-vertex polygon resolves all of them. `map_get_closest_point` then snaps queries out to the nearest polygon EDGE — and path endpoints are resolved through exactly that.

Measured on s3's authored terrain, over every 5-tile diagonal move whose straight line is fully walkable: one quad per cell bends 22% of them (mean excess 4.1%); the merged mesh bent **87%** (mean **24.8%**). The merge made real maps about five times worse while making the synthetic flat case perfect — which is why the flat-square benchmark alone is not enough to validate a change here. Both engine behaviours are pinned in `tests/test_NavPathDirectness.gd` so a repeat attempt fails in seconds.

Straightening paths therefore happens AFTER the path is returned — see §Path straightening below, which is built.

#### The A* polygon budget must be raised (`Movement.PATH_SEARCH_MAX_POLYGONS`)

Godot defaults `NavigationAgent3D.path_search_max_polygons` to **4096 — fewer polygons than this game's navmesh has.** One quad per cell means an s1-sized map bakes ~12,500 polygons per agent class, so any path forced to detour around a sizeable obstacle exhausts the budget. The server then returns a **PARTIAL path rather than an error**, and the unit walks as far as the search reached and stops — which reads exactly like "it refuses to path around the mountain", and is indistinguishable from unreachable unless you inspect the returned path's endpoint.

Measured on a 159x159 map, ground to a plateau top reachable only by a ramp on the far side: at the default budget the query returned 43 points ending **17.2 units short** at the base of the cliff; with the budget raised, the same query returned 109 points ending exactly on target. Every individual leg of that route reported connected, which is what gives the bug away — connectivity is transitive, so legs that all connect while the whole does not means the search gave up, not that the route is missing.

Raising it is close to free: it is a CAP, not a preallocation, so a short path still explores only what it needs. `configure_for_map` sets it on every agent.

#### Path straightening (`Movement.string_pull`)

**`Movement.get_next_path_position()` returns the FURTHEST waypoint the unit can reach in a straight line, not the next one.** That one seam is the whole mechanism — `CommandReceiver` steers with `direction_to(get_next_path_position())`, so every consumer is fixed at once and nothing else changed.

The corridor is why. A* hands the funnel a STAIRCASE of unit cells, and the funnel returns the shortest path *inside that corridor* — for any heading that is not axis-aligned or exactly diagonal, a bowed polyline, because the straight line lies outside the corridor and is not available to it. Measured on flat, empty ground with a single unit: a 12-unit move at 30° came back bowed **1.45 units** off the straight line, every segment 12–19° off the ordered heading.

**Heading error is the metric; path length hides this almost completely.** The bow goes out and comes back, so the polyline is only ~1% longer while the direction is wrong the entire way. Ordered headings measured on one unit in empty space, before and after:

| Ordered | 0° / 45° / 90° / 135° / 315° | 15° | 30° | 60° | 75° | 200° |
| --- | --- | --- | --- | --- | --- | --- |
| before (mean / max) | 0.00° | 12.8 / 27.3° | 10.6 / 32.5° | 10.6 / 32.5° | 13.1 / 27.3° | 16.0 / 33.3° |
| after | 0.00° | **0.00°** | **0.00°** | **0.00°** | **0.00°** | **0.00°** |

Axis-aligned and exact-diagonal headings were always perfect — they are the two directions a square-quad corridor can represent — which is the fingerprint that separates this from RVO in the first place.

**Godot's `NavigationAgent3D.simplify_path` does NOT fix it, and was measured rather than assumed.** It is Ramer–Douglas–Peucker over the polyline's own geometry: it can only DELETE points, knows nothing about what is walkable, and so cannot move the path onto the straight line. At epsilon 0.5 it left the 200° bearing's mean error *worse* (15.97° → 23.85°). `path_postprocessing` is already CORRIDORFUNNEL.

Three things keep it honest:

- **The reachability test is `TerrainGrid.is_navigable_for`, with THIS unit's erosion parameters** — not a navmesh query. `NavigationServer3D`'s closest-point query is not filtered by navigation layer, so it would answer for the un-eroded base mesh and let a large unit cut a corner it does not fit through. The grid already keeps a precomputed clearance field, so the test is a handful of array reads, and `get_navigable_cells` calls the same function, so the bake and the string-pull cannot drift apart.
- **The agent is still asked for its next position every tick**, even when the pulled target is used. That call is what advances the agent's internal cursor; skipping it strands the agent on waypoint 0.
- **The destination is tested first; otherwise the search runs back from the furthest waypoint within `STRING_PULL_REACH_CELLS` of the unit, never past the agent's next waypoint,** and the answer is cached for `STRING_PULL_RECHECK_TICKS`. On open ground the destination is reachable, so the common case is one line test. A line test walks exactly the cells the segment crosses, once each, and stops at the first refusal (`TerrainGrid.is_segment_navigable_for`).

Obstacle routing is unaffected: on the plateau map a unit ordered diagonally past the cylinder still goes around it (detour ×1.12 → ×1.07, i.e. straighter but still around), while an open-ground crossing went ×1.14 → ×0.96 and arrived 17% sooner. Tests: `tests/test_StringPullNavigability.gd` pins the cell rule (including that a 2×2 unit is refused a one-cell gap); the end-to-end measurement is `tools/terrain_meshes/probe_velocity_angle.gd` against `scenes/scenarios/test/nav_straight_line.tscn`, an empty flat scenario built for exactly this.

#### What path straightening costs, and why the search is bounded that way

Around an obstacle A* returns about **one waypoint per cell** (134 waypoints for a 133-unit
route on the plateau map), because the corridor is a staircase of unit quads. The first search
tested every waypoint back from the far end whenever the destination was out of sight, each
with a line sampled twice per cell: waypoints × path length per recheck. In a five-minute
bot-vs-bot skirmish that was **3.6 ms per tick, 45% of all unit and structure script time**, and
one unit on a bad path produced a spike every recheck — 98 of the match's spike gaps were
exactly `STRING_PULL_RECHECK_TICKS` long.

Bounding the search by a reach, and walking crossed cells instead of sampling, measured
(2026-09-26, same skirmish, per tick):

| reach | string-pull cost | routes past the plateau obstacle (walked ÷ straight) |
|---|---|---|
| whole path (before) | 3.63 ms | ×1.144, ×1.069, ×1.051, ×1.051 |
| 64 cells | 1.73 ms | ×1.082, ×1.069, ×1.051, ×1.052 |
| **32 cells (shipped)** | **0.68 ms** | ×1.084, ×1.076, ×1.057, ×1.058 |
| 16 cells | — | ×1.101, ×1.122, ×1.076, ×1.076 |

The first route got *better*: the old search went all the way back to waypoint 0, so a unit
with nothing ahead in view could steer at a waypoint it had already passed. At 64 cells the
routes match an unbounded search exactly; 32 costs under 1% of route length for 2.5× less
work. Open ground is unaffected at any reach (the heading probe reads 0.00° at every bearing,
tick for tick identical), because there the destination is in view.

- **REJECTED — searching forward from the next waypoint and stopping at the first one out of
  sight.** It is cheapest, but past a bend the path drops out of view and comes back, and the
  forward search stops short: routes around the plateau came out ×1.110–×1.203, several percent
  longer, one hitting the probe's tick limit.

#### Re-planning after a navmesh change

**A ground unit owns its path; `NavigationAgent3D` is kept for avoidance only.** The agent
re-plans on *every* navigation map change, and nothing turns that off (Godot 4.7:
`agent_is_map_changed` forces a synchronous `query_path` inside `is_navigation_finished` /
`get_next_path_position`). Every structure placed or destroyed changes the map, so every
moving unit re-planned in the same tick — 25–36 queries at ~1.2 ms, **25–65 ms in one tick**,
the largest spikes left after path straightening. `Movement` therefore queries and follows its
own path with the agent's settings and the agent's waypoint and arrival rules, and differs in
one rule only: **it re-plans on a map change only when the change reaches its path.**

- **`NavManager` records each rebuild as a `NavChange`**: the changed cells grown by the widest
  size class's reach, as a world rectangle. A change is **landed** once every rebuilt region
  has processed its mesh *and* the map has published an iteration that includes it — the same
  sync, on the project's synchronous map; a later iteration on an async one. A unit never
  re-plans on a change before it has landed, or it would plan on the old mesh.
- **A unit re-plans when a landed change crosses the rest of its path**, the leg from where it
  stands included.
- **A path that stops short of its target re-plans on a change around the target** — within one
  cell more than the gap it stops short by — since that is where a change could open the way.
  A unit attacking a structure is the common case: its target is inside the footprint, so its
  path always stops short. Re-planning such paths on *any* change was tried first and was most
  of the remaining cost (498 of 691 checks in one match).
- **A unit that falls behind the change history (`NavManager.CHANGE_HISTORY`) re-plans.**
- **Accepted pitfall: a change that opens a shortcut away from a unit's path is not taken until
  that unit next re-plans for another reason** — a new order, straying `path_max_distance` off
  its path, or a change that does cross it. Destroying a wall beside a column's route no longer
  bends the column through the gap.

INVARIANT: nothing may ask the agent itself for a path — its own query runs, and its own
"finished" transition then stops it passing velocities to avoidance. No API can prevent the
call; `Movement` is the only way in, and every path question goes through it.

Measured (2026-09-27, five-minute skirmish, per tick, the worst tick within ten of each
structure change, time spent reading paths):

| | median | worst |
|---|---|---|
| the engine's agent: every unit re-plans | 35.6 ms | 65.8 ms |
| crossing rule, short paths re-plan on any change | 16.5 ms | 39.7 ms |
| **crossing rule, short paths re-plan near their target (built)** | **3.8 ms** | **21.5 ms** |

Movement itself is unchanged: headings, arrival ticks and the four plateau routes come out
identical to the agent's own following, tick for tick. Tests:
`tests/test_NavChangeReplanning.gd`.

#### A path is the straight line whenever the unit can walk it

**When a unit's own size class can walk the straight line to its target, that line is its
path, and the navmesh is not queried** (`Movement._plan_path`, decided 2026-09-27). It is the
line path straightening would steer along anyway, tested by the same crossed-cell rule, so the
unit moves identically — the heading probe and the plateau routes are unchanged. What it saves
is the query: each tick `CommandReceiver` sets a pursuer's goal to where its quarry is now, and
any change of goal discards the path, so a chaser used to re-plan on every tick its quarry
moved. In a fight the quarry is usually in plain sight.

A straight path is re-planned like any other: by a navmesh change that crosses it, by straying
off it, or by a new target — and the re-plan tries the straight line first again.

Measured (2026-09-27, the same skirmish twice each way, one after the other, under the per-
function timers on a loaded machine — so compare the pairs, not the absolute values):

| | path queries per tick | query time per tick |
|---|---|---|
| navmesh query for every plan | 1.4 / 2.6 | 1.6 / 2.9 ms |
| **straight line when clear (built)** | **0.4 / 0.7** | **0.6 / 0.8 ms** |

**What a chaser still does when its quarry is out of straight-line reach: re-plan on every tick
the quarry moves.** Each of these was researched and is a candidate if that shows up:

- **TODO — re-plan when the goal has moved far, relative to how far away it is.** The A*
  Pathfinding Project's `Dynamic` policy: re-plan at once if the new destination leaves a
  circle around the old one of radius *distance ÷ sensitivity* (default 10), otherwise at the
  latest after `maximumPeriod` (default 2 s)
  ([AutoRepathPolicy](https://arongranberg.com/astar/docs/autorepathpolicy.html)). Unreal's
  path following does the same with a fixed *tether distance* around the last path point. The
  strongest candidate: near quarries still update quickly.
- **TODO — re-plan on a timer, staggered across units.** The usual RTS answer is every 1–2 s
  ([GameDev.net](https://gamedev.net/forums/topic/389941-hunting-the-enemy-rts/3580384/)).
  Spring/Recoil rate-limits a unit's path requests outright (`pfRepathMaxRateInFrames`,
  default 5 s) and re-plans when a unit stops making progress, not when it merely touches
  something ([Recoil changelog](https://recoilengine.org/changelogs/archive/)).
- **TODO — aim ahead of the quarry.** Reynolds' pursuit steers at its position plus
  velocity × T, with T proportional to distance
  ([Steering Behaviors](https://www.red3d.com/cwr/steer/gdc99/)); a behaviour change, not only
  a cost one, so it wants a design decision.
- **TODO — incremental search** (Moving Target D* Lite, ~4–5× faster than re-planning from
  scratch; [Sun, Yeoh, Koenig 2010](https://idm-lab.org/bib/abstracts/papers/aamas10a.pdf)).
  It reuses the previous search tree, so it needs our own A*; Godot's server does not expose
  one. Only if queries become the dominant cost again.
- **REJECTED — time-slicing many simultaneous searches.** Rabin and Sturtevant list it as a bad
  idea: separate open lists thrash memory; make each search cheap instead, or split fast and
  slow requests into two queues
  ([Game AI Pro ch. 17](https://www.gameaipro.com/GameAIPro/GameAIPro_Chapter17_Pathfinding_Architecture_Optimizations.pdf)).

#### Where "units walk in L shapes" usually comes from: avoidance, not paths

Before touching pathfinding, check whether the path is even bent. A unit ordered 5 tiles diagonally out of a **stationary** cluster of its own squadmates gets an exactly straight path and still veered ~0.4 cells sideways, travelling in legs at 63°, then 34°, then 41° instead of a clean 45° — entirely RVO against the neighbours it was standing among.

The way to tell the two apart is to log the trajectory: boot the scenario headless, issue the order, and sample `global_position` per physics tick against `Movement.get_next_path_position()`. A bent PATH shows as waypoints off the straight line; an avoidance veer shows as straight waypoints with the body bowing off them and returning.

**Telling the two apart takes seconds, and the fingerprint is HEADING.** Bending from the navmesh is a function of which way the unit is going; RVO veer is a function of who is standing nearby, and cannot depend on compass direction. Sweep `NavigationServer3D.map_get_path` over many headings (no simulation needed — `tools/terrain_meshes/probe_path_bend.gd`) and a corridor problem prints this shape, measured on flat open ground at a 5-unit move length:

| Heading | Bent | Mean excess |
| --- | --- | --- |
| 0 / 90 / 180 / 270 (axis-aligned) | 0% | 0.00% |
| 45 / 135 / 225 / 315 (exact diagonal) | ~10% | 0.20% |
| everything else | 81% | 1.41% |

Those are the two directions a square-quad navmesh can represent exactly; every heading between them bends. **Excess grows sharply with move length** — 0.75% mean at 5 units, 2.1% at 10, 4.3% at 20, **10.1% at 40** (worst case 34%) — so it is most visible on a big open map where orders are long, and it is NOT a property of any particular map: s1 measures 76.4% bent / 9.20% mean at a 20-unit length, marginally worse than the mesh-baked test maps' 75.5% / 8.18%.

The companion check is `tools/terrain_meshes/probe_pathing.gd`, which runs the same move twice — once with every other unit teleported away, once with them clustered around the start — and reports the A* path length beside the body's maximum offset from that path. Avoidance shows as a gap between the two runs; a corridor problem shows as identical runs with a path already longer than the straight line (measured on a 23-degree, 48.8-unit move: path x1.177 and body offset 0.37, **identical isolated and clustered**).

**Firers outrank travellers, travellers outrank standers** (`Movement.update_avoidance_priority`, ticked from `Actor._physics_process`). RVO is reciprocal: two equal-priority agents each take half the responsibility for not colliding, so a stationary neighbour that never pays its half leaves the mover re-steering — and arcing. Godot's `avoidance_priority` decides who yields (an agent does not adjust for LOWER-priority neighbours, which pushes the adjustment onto them), so a unit that is travelling is ranked above one that is standing still. Measured on the case above: lateral deviation 0.39 → **0.000**, arrival 95 → 87 ticks, closest approach between bodies unchanged at 0.41 (2× the 0.2 agent radius, so nothing clips).

- **The avoidance work is conserved, not removed.** Someone has to leave the line when a unit is standing on it; this chooses the bystander, which steps ~0.4 cells aside and stays there. That is the intended trade — a unit under orders should look like it is going where it was sent.
- **A unit firing from where it stands outranks both, and yields to nobody** (`MoveCommand.holds_ground` — `Attack` and `FocusFire` in reach). This is an execution-elasticity choice, not a pathing one: a unit that has started shooting obstructs the friendly units behind it, so a player who wants them in range has to kite, concave or re-space — see [elasticity](../../design-framework/elasticity.md). TODO: acquisition ranks by target priority and then distance across the whole aggro range, so a unit with a low-priority target in reach walks on toward a higher-priority one out of reach rather than stopping to fire. Whether an in-reach target should win is undecided: winning makes units plant and obstruct sooner; losing keeps target priority absolute.
- **Otherwise keyed on `is_navigation_finished()`, not on having a command**, so anything else that is stopped yields alike (idle, holding a position) and regains its rank the tick it moves. A unit whose path is still being computed reads as standing for one tick, which is harmless.
- The engine clamps priority to [0, 1], so `ENGAGED` takes the ceiling and `TRAVELLING` sits at 0.75, below it. Only the ordering is meaningful.
- A group ordered together is untouched: they share a rank, so it is ordinary reciprocal RVO (measured 0.023 lateral).
- `neighbor_distance` was the other candidate lever and was NOT used. Dropping it from 2.5 to 1.0 also cuts the bow (0.39 → 0.05), but it does so by making units notice each other later, which degrades avoidance everywhere to fix one case — and it still shoves the bystander 0.40. Priority states the actual rule.

Tests: `tests/test_AvoidanceYielding.gd` pins the ranking. It does not re-measure the trajectory — a live NavigationServer can't be driven headlessly the way the one-off harness did (boot the scenario, `simulation_clock.clear()`, order a unit, sample per tick).

## An unreachable destination is left alone

A ground order may name a point no walking unit can reach — most often a cell inside a **disjoint
navmesh component**, which the terrain model deliberately allows (a dry chasm floor is walkable and
reachable only by air; see [map-composition.md](map-composition.md)). It also happens transiently
whenever a structure goes up across the only corridor.

**The order is issued with the clicked point verbatim, and the navigation agent does the rest.**
Godot's path query already returns a route to the closest reachable point, so the unit walks as far
toward the destination as the mesh permits and stops. That is the whole handling; nothing detects
the case and nothing corrects it.

**The rejected alternative is clamping the destination** to the nearest navigable point before
issuing the order. It leaks map knowledge: the waypoint would visibly jump off the clicked cell to
the edge of the reachable region, which tells the player exactly where the boundary of an
inaccessible area lies — information the terrain is supposed to make them read off the geometry,
and information about ground they may not even have explored. A best-effort walk reveals nothing
the player could not already see.

`CommandReceiver._resolve_movement_target` is where this holds: a ground click passes through as
`message.position`, unmodified. (`_resolve_movement_target` *does* redirect a **structure**-targeted
order onto a footprint-adjacent cell — that is a different thing, and it is about approaching a
building each unit's own way rather than about reachability.)

**The `Bot` is deliberately not held to this.** `BotActuator` snaps its destinations with
`Map.nearest_navmesh_point` before issuing them, which is correct — a bot clamping its own orders
tells no player anything. Do not "unify" the two paths; the asymmetry is the point.

## Avoidance priority: firers, then travellers, then standers

*Moved out of `movement.gd::update_avoidance_priority`.*

RVO is reciprocal: two equal-priority agents each take half the responsibility for not
colliding. When one of them is standing still and never moves, that half is never paid,
so the mover has to keep re-steering and ends up arcing around it. That is the whole of
the "why is my unit walking in L shapes" report: ordered five tiles diagonally out of a
cluster of its own idle squadmates — one of them standing exactly on its line — a unit
bowed 0.39 cells sideways and travelled in legs at 63°, 34° and 41° instead of a clean
45°. The path underneath was already exactly straight, so no amount of pathfinding work
would have touched it (see the note after NavManager._build_chunk for the fix that did not work).

Godot's avoidance_priority says who yields: an agent does not adjust for neighbours of
LOWER priority, which pushes the adjustment onto them instead. Ranking travellers above
standers therefore hands the sidestep to the unit that is not going anywhere, and the
mover holds its heading — measured at 0.000 lateral deviation, with the gap between
bodies unchanged at 0.41 (2x the 0.2 agent radius), so nothing clips.

The work is CONSERVED, not removed: someone has to leave the line, and this chooses the
bystander. It steps aside about 0.4 cells and stays there. That is the intended trade —
a unit under orders should look like it is going where it was sent, and a unit standing
around is the one with nothing better to do.

A unit standing still to FIRE is the exception: it outranks travellers and yields to
nobody (see the list above). Otherwise it is keyed on is_navigation_finished() rather than
on having a command, so a unit stopped for any other reason yields alike, and regains its
rank the tick it starts moving again. A unit whose path is still being
computed reads as standing for that one tick, which is harmless.
