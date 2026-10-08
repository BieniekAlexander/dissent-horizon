# Navigation agent size classes (space-eroded per-class navmeshes)

This documents how unit width is accounted for in pathfinding, the prior research
that led here, the implementation, and the limitations / fallback if we ever want
to revisit the decision.

## The problem

The navmesh is built one quad per passable cell (`NavManager`, `TerrainGrid`).
With a single shared navmesh, the corridor-funnel pathfinder routes paths straight
to building **corner vertices**, so units visibly clip / "walk through" building
corners as they round them. Two things that look like they should fix this don't:

- `NavigationAgent3D.radius` only feeds **RVO avoidance** (agent-vs-agent spacing),
  not the path's offset from static navmesh edges.
- `NavigationMesh.agent_radius` (which normally erodes walkable polygons away from
  obstacles by the agent radius) is **only applied during Godot's geometry bake**.
  We build the mesh by hand with `add_polygon()` and never bake, so it's ignored —
  and CLAUDE.md forbids switching to the bake path.

A naive single eroded navmesh fixes corners but bakes in **one** radius, so it
can't serve units of different widths.

## Prior art (research, 2026-06)

How cell-grid RTS games handle variable unit widths:

- **StarCraft: Brood War** — no per-unit grid erosion, no clearance precompute.
  Uses a fine **8×8-pixel walk grid** (16× finer than the 32×32 build grid),
  rectangular per-unit collision boxes, **region/chokepoint** high-level pathing,
  per-step "is the tile ahead occupied?" re-planning, plus hacks (mining workers
  ignore mutual collision). Brute: finer grid + footprint test + local repair.
  Famously buggy (Dragoon sticking).
  - Sources: [Code of Honor — the StarCraft path-finding hack](https://www.codeofhonor.com/blog/the-starcraft-path-finding-hack),
    [BWAPI guide](https://makingcomputerdothings.com/brood-war-api-the-comprehensive-guide-of-time-and-space/)
- **Age of Empires II** — three pathfinders + **two obstruction systems**. Static
  buildings = **square** tile obstructions on a shared grid (high-level mip-map +
  tile pathfinder); per-unit width is a **circular radius** resolved in a separate
  **continuous polygonal / convex-hull** layer, *not* by eroding the grid. Unit
  size lives in the local continuous layer.
  - Source: [openage reverse-engineering doc](https://github.com/SFTtech/openage/blob/master/doc/reverse_engineering/game_mechanics/pathfinding.md)
- **Clearance-based pathfinding / Annotated A\*** (Harabor & Botea) — the principled
  version: precompute a per-cell **clearance** (distance-to-obstacle / largest-square
  fit) **once**; A\* admits a cell for a unit of size `S` iff `clearance(cell) >= S`.
  One annotation serves every size. But it assumes you **own the A\*** — we pathfind
  via `NavigationServer3D` + `NavigationAgent3D`, so we don't.
  - Source: [harablog — clearance-based pathfinding](https://harablog.wordpress.com/2009/01/29/clearance-based-pathfinding/)

## Decision: Option B — per-size-class eroded navmeshes

We bake **one navmesh per discrete size class** as a separate **region on a single
shared `NavigationServer3D` map**, each tagged with a distinct `navigation_layers`
bit; an agent selects its class's mesh via `NavigationAgent3D.navigation_layers`.
This keeps all of Godot's nav (no custom A\*), handles varying widths, and is the
AoE2-style "static grid, size handled per-class" idea bucketed into a small N.

**One map, not one-map-per-class — this matters.** Godot computes RVO avoidance
*per navigation map*. An earlier version of this feature gave each class its own map
(`set_navigation_map`); that siloed avoidance so units on different maps (and, in
practice, units generally) passed through each other. The fix is the single shared
map above: `navigation_layers` gates **pathfinding region selection only**, never
avoidance, so every unit avoids every other unit regardless of size class. Per-class
regions set `use_edge_connections = false` (each class mesh is self-contained and must
not bleed into another class's mesh).

Three classes (`NavAgentClass.Size`). **The class IS its corridor width in whole cells**;
everything else is derived from that tier, so classification and erosion cannot drift apart.
Radii in world units at `Map.CELL_SIZE = 1.0`:

| Class  | corridor | radius `r` = tier·cs/2 − 0.05 | e.g.                      |
|--------|---------:|------------------------------:|---------------------------|
| SMALL  | 1 cell   | 0.45                          | infantry                  |
| MEDIUM | 2 cells  | 0.95                          | the Stock Truck (body 0.7)|
| LARGE  | 3 cells  | 1.45                          |                           |

A body takes the smallest class whose radius covers it, so the Stock Truck's 0.7 is MEDIUM.

### Erosion pipeline (per class, radius `r`, cell size `cs`)

Whole-cell quads can't be eroded by a sub-cell radius without either over-eroding
or leaving corner clipping. So we combine **two** steps — derived purely from the tier
and `cs` (`NavAgentClass`):

```
rings   = floor(r/cs)        # whole-cell layers stripped near obstacles  {0,0,1}
admit_k = tier               # min corridor width in cells (covering gate) {1,2,3}
inset   = r - rings*cs       # sub-cell trim applied to the built mesh      {.45,.95,.45}
```

1. **Cell gate** (`TerrainGrid.get_navigable_cells(rings, admit_k)`): a cell is in
   the class's set iff it is passable, survives **ring-erosion** (Chebyshev
   distance-to-obstacle/out-of-bounds `> rings`), **and** is coverable by an
   `admit_k × admit_k` block of passable cells. Ring-erosion keeps big units cells
   away from obstacles (and keeps the inset safe); the covering gate enforces the
   1/2/3-cell hallway admission and drops corridors too narrow to inset without
   collapsing. (`admit_k` uses an anchored largest-square clearance DP; ring-erosion
   uses a Chebyshev distance transform — both precomputed once per navmesh rebuild,
   dirty-flagged on cell changes.)
2. **Sub-cell boundary inset** (`NavManager`): each boundary vertex of the built mesh
   is moved toward the walkable interior by `inset` (in corner-index units `inset/cs`),
   along the normalized sum of directions to its **included** incident cells. Shared
   vertices move once, so the mesh stays connected. This is the actual corner-clip
   fix; it rounds the inner (concave) corner a unit would otherwise clip. Because
   `inset < cs` after ring-erosion and surviving corridors are `>= admit_k` wide,
   the inset never overshoots an interior vertex (no inverted/degenerate quads).
   Verified per class: leftover corridor width `admit_k*cs - 2*inset` is
   `{0.6, 0.2, 0.6, 0.4}` — all positive.

The base scene `NavigationRegion3D` keeps an **un-eroded** mesh (`rings=0, admit_k=1,
inset=0`) on the default world map, so `Map.get_navmesh_line_hit` and
`EventCommandPoint` target-snapping (which query `nav_region.get_navigation_map()`)
keep working against the full passable surface.

## Wiring

- **Class is auto-derived, not authored.** `NavAgentClass.class_for_radius(r)` returns
  the smallest class whose radius is `>= r` (clamped to MASSIVE for oversized bodies):
  a 0.3-radius body → MEDIUM (0.4), the tightest class it fits.
- `Movement.configure_for_map(nav_manager, shape_radius)` sets the RVO avoidance
  radius to the unit's *true* MovementBody footprint (`set_agent_radius(shape_radius)`),
  derives the class from `shape_radius`, and sets
  `_nav_agent.navigation_layers = nav_manager.layer_for(class)`. The agent STAYS on the
  shared default map (it never calls `set_navigation_map`), so avoidance is map-wide;
  only the pathfinding region (class mesh) differs. So avoidance uses the real footprint
  while the navmesh is class-bucketed (eroded by the class radius, which is `>=` the
  footprint).
- `NavManager.layer_for(size)` = `1 << (size-1)` (SMALL→bit0 … MASSIVE→bit3); the base
  un-eroded region uses a reserved bit (`1<<30`) no agent selects.
- Called from `Actor._on_commander_changed` (the first point where `map` is set
  for both dynamically-spawned and scene-placed units), next to `enable_avoidance()`,
  passing `bounding_radius(MOVEMENT_OBSTRUCTION)` — the MovementBody shape radius.
- `Movement.nav_agent_class` is the resolved value (a plain var, for introspection),
  no longer an `@export`.

## Reaching a building

Erosion is right for walking and wrong for "am I next to it?". Two rules follow, and both
exist because a loaded Stock Truck parked beside its Compound and never deposited.

**Close enough includes a class standoff.** The grid rule — the unit's cell within one cell
of the footprint — assumes the unit can stand in a touching cell. A MEDIUM mesh is inset
0.95 from every wall, leaving 0.05 of that cell reachable: in practice never. So a unit is
also close once it is within its class radius plus one cell of slack of the footprint (the
agent halts ~0.5 short of its mesh's nearest point, and the inset is a chamfer). For SMALL
this barely widens the grid rule; for MEDIUM and up it is the only rule that can pass.
Shared by Build, Assemble, Repair, Capture and Interact, since all ask the same question.

**The approach cell is chosen by a real path.** Standable is not reachable: a pocket walled
in by neighbouring buildings passes the class's cell gate while its only exits are one-cell
gaps. Nearest-by-distance picked exactly such a pocket beside a bot's Compound, and the
agent stopped as close as its mesh allowed and re-resolved the same cell every tick. The
candidates are now ranked by distance and the first one a path on the unit's own class
layer actually reaches is taken — one query per candidate, memoized for the life of the
command. When none is reachable it falls back to the nearest, and the unit waits.

**Bots keep their bases passable for the widest class.** Rules 1 and 2 of `NavPlacement`
ask about passable cells, which is the SMALL unit's view: a one-cell gap is a route to it.
A bot packing buildings round its Compound (Work Detail rewards touching) sealed it off
from its own MEDIUM trucks that way — one Compound in a 12-minute bot mirror. So a bot
placement must also pass rule 3 (`NavPlacement.accepts_for_class`) for LARGE, the widest
class there is (`BotEconomy.PLACEMENT_NAV_CLASS`): it may not disconnect ground that
class could reach, may not take the last reachable approach from a nearby building, and
the new building must itself have one. In practice no gap between buildings narrower than
three cells, unless it is a gap nothing needed. The rule recomputes the class gate only in
the band a footprint can change and reads the grid's precomputed answer elsewhere; the
bot's placement cost did not measurably change.

TODO: a wide unit must always be able to reach a building's WALL — close enough to crush a
unit standing against it. Today a Shelter resident (SMALL) pressed to the Shelter's wall is
where a Stock Truck's eroded mesh cannot go; the truck re-issues the move every few ticks
and waits for the resident to wander out (5–100 s measured). Wander usually frees it, which
is why this is deferred rather than urgent. The requirement is settled; the mechanism is
not — the class inset stops a MEDIUM unit 0.95 from any wall, and crush contact needs the
bodies to touch.

## Limitations / future work (if revisiting this decision)

- **Cell-granular admission.** Hallway gating is in whole cells; the radii are tuned
  for `CELL_SIZE = 1.0`. If `CELL_SIZE` changes, re-check the `{rings, admit_k, inset}`
  table values per class.
- **Discrete classes, not continuous.** Adding a 5th width = a 5th map. Fine for a
  handful of footprints; if unit sizes become continuous, the clearance-field +
  **custom grid A\*** route (Annotated A\*, stepping off `NavigationAgent3D` path
  queries) is the principled replacement — see research above.
- **Inset is a single chamfer, not a true Minkowski offset.** Corners are cut, not
  perfectly rounded. A full polygon-offset erosion would be more accurate but fights
  the shared-vertex quad topology (holes, miters, swallowed cells). TODO, not built.
- **One navmesh per class is shared by all units of that class** (the class regions
  are global). Per-instance exceptions are still handled by RVO (`AvoidanceAgent3D`).
- **Avoidance is map-wide by design** (all classes share one map). If a future change
  ever needs per-class maps, remember it will silo avoidance — keep `navigation_layers`
  region filtering instead.
- SMALL and MEDIUM produce identical cell gates (`admit_k=1, rings=0`); they differ
  only in `inset` and the agent RVO `radius`. Kept as separate maps for uniformity.
