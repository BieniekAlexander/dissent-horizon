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

Four classes (`NavAgentClass.Size`), radii in world units:

| Class   | radius `r` | intent                                  |
|---------|-----------:|-----------------------------------------|
| SMALL   | 0.2        | navs comfortably between cells           |
| MEDIUM  | 0.4        | fits single-file through a 1-cell hallway|
| LARGE   | 0.7        | can only fit through 2-cell hallways     |
| MASSIVE | 1.3        | can only fit through 3-cell hallways     |

These radii are chosen for `Map.CELL_SIZE = 1.0`: a corridor of world-width `Wd`
admits radius `r` iff `Wd >= 2r` (diameter), which reproduces the hallway column.

### Erosion pipeline (per class, radius `r`, cell size `cs`)

Whole-cell quads can't be eroded by a sub-cell radius without either over-eroding
(closing the 1-cell hallways MEDIUM must use) or leaving corner clipping. So we
combine **two** steps — derived purely from `r` and `cs` (`NavAgentClass`):

```
rings   = ceil(r/cs) - 1     # whole-cell layers stripped near obstacles  {0,0,0,1}
admit_k = ceil(2*r/cs)       # min corridor width in cells (covering gate) {1,1,2,3}
inset   = r - rings*cs       # sub-cell trim applied to the built mesh      {.2,.4,.7,.3}
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
- Called from `Commandable._on_commander_changed` (the first point where `map` is set
  for both dynamically-spawned and scene-placed units), next to `enable_avoidance()`,
  passing `bounding_radius(MOVEMENT_OBSTRUCTION)` — the MovementBody shape radius.
- `Movement.nav_agent_class` is the resolved value (a plain var, for introspection),
  no longer an `@export`.

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
  the shared-vertex quad topology (holes, miters, swallowed cells). Deferred.
- **One navmesh per class is shared by all units of that class** (the class regions
  are global). Per-instance exceptions are still handled by RVO (`AvoidanceAgent3D`).
- **Avoidance is map-wide by design** (all classes share one map). If a future change
  ever needs per-class maps, remember it will silo avoidance — keep `navigation_layers`
  region filtering instead.
- SMALL and MEDIUM produce identical cell gates (`admit_k=1, rings=0`); they differ
  only in `inset` and the agent RVO `radius`. Kept as separate maps for uniformity.
