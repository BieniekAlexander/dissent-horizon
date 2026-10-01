---
title: Visual facets (map generation pass 7)
type: system-note
---

# Visual facets — map generation pass 7

*Design note for [Dissent Horizon](../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md
carries only the pointer.* The pass sits at the end of [map-generation.md](map-generation.md)'s
pipeline; how the result is DRAWN is [ux/aesthetics/terrain-readability.md](../ux/aesthetics/terrain-readability.md).

**Pass 7 derives a map's cosmetic layer — ground paint, trails, doodads, and the sites of later
set dressing — from the map alone.** It is a proof of concept: every shape, palette and density
is a placeholder (Alex, 2026-10-01: fidelity is not the goal; the visual language comes later).

---

## Derived, never saved

Decided 2026-10-01 (Alex): **the decoration is derived at map load, and the generator applies
the same step after generating.** One pure function, `MapDecorationPlanner.plan`, runs in both
places over one input form, `MapDecorationInput`, built either from a `GeneratedMap` or from a
loaded `Map`. Nothing is written into the map scene; `Map` adds its `MapDecorator` child
unowned. The test that holds this together is that a generated map and the scene written from
it decorate identically (`test_MapDecoration`).

- **Hand-authored maps get decoration too**, because nothing about it depends on having been
  generated.
- **No stored seed.** The seed is a hash of the terrain's own heights, ground materials and play
  size, so two loads agree and an edit re-rolls it.
- **Starts are not an input.** Spawn points are hidden from players
  ([map-generation](map-generation.md) §Shelters); paint or a trail converging on one would give
  it away. Shelters are input, and are shown at match start anyway.
- REJECTED — baking decoration nodes into the generated scene: only generated maps would get
  it, and it would go stale under the brush exactly as the surface mesh does (CLAUDE.md
  §Regenerating data).

## Cosmetic only

Decided 2026-10-01 (Alex): **nothing here has gameplay effect** — no footprint, no navigation,
no vision. Because a player cannot tell a cosmetic prop from an obstacle by looking, **a prop
taller than `DoodadLibrary.LOW_MAX_HEIGHT` stands only on ground no unit can walk** (impassable
cells); walkable ground carries only knee-high props. `MapDecorationPlanner.is_admissible`
enforces it, and a test pins it. Nothing stands on a fixture, its 1.5-cell margin, a trail, or
deep water, and a structure placed later hides the props under it (`MapDecorator.clear_cells`).

## What it produces

| Output | Rule |
|---|---|
| **Meadow** paint (overlay R) | around settlements (neutral buildings and shelters), fading over `MEADOW_RADIUS_CELLS`, plus noise-driven clearings anywhere |
| **Trails** (overlay G) | settlements — buildings within `SETTLEMENT_LINK_CELLS` of each other are one — joined by a minimum spanning tree, each edge routed by A* over walkable ground (wading and slopes cost extra, noise bends it). Edges longer than `TRAIL_MAX_LENGTH_CELLS` are dropped |
| **Scree** (overlay B) | walkable ground within `SCREE_RADIUS_CELLS` of a cliff or barrier |
| **Shore** (overlay A) | shallow water and dry ground within `SHORE_RADIUS_CELLS` of water |
| **Doodads** | trees, dead trees, boulders on impassable ground (grouped into stands by noise); rock piles and bushes along cliff feet; reeds on shallow edges; flowers in meadows; stumps near settlements; grass tufts anywhere |
| **Facet sites** | cells where later dressing goes — see below. Detected, not dressed |

## Shortlist: what is worth generating

Ordered by how much each does for reading the terrain, given the features the generator makes
today (ridges, chasms, mountains, lakes, rivers, ponds, tiers, ramps, settlements).

| # | Facet | Terrain it follows | State |
|---|---|---|---|
| 1 | **Cliff faces** — rock-face meshes along a cliff run | tier cliffs, barrier edges (`Facet.CLIFF_FACE`) | PLANNED: sites detected; today the shader's rock bands and ink line stand in |
| 2 | **Ramps** — a worn path or steps on the way up | pass 6 ramps (`Facet.RAMP`) | PLANNED: sites detected (heuristic: a sloped walkable cell with cliff on opposite sides within 20 cells; TODO: unvalidated against pass 6's own ramp list, which a loaded map does not keep) |
| 3 | **Mountain massifs** — peak models over a grown ridge's core | obstacle-region mountains (`Facet.MOUNTAIN`) | PLANNED: core detected; trees and boulders stand in |
| 4 | **Shorelines** — wet band, reeds, foam | lakes, rivers, ponds (`Facet.SHORE`) | built as paint and reeds; foam PLANNED |
| 5 | **Waterfalls** — where chasm water stops short of a level drop | the dry two-cell gap of [map-generation](map-generation.md) §5 (`Facet.WATERFALL`) | PLANNED: lip detection built; it found none on the review maps, which is unverified rather than proven correct (TODO) |
| 6 | **Fords and land bridges** — stepping stones across a carved chasm | pass 4 carves through flooded cuts | TODO: not detected; needs the carve list, which a loaded map does not keep |
| 7 | **Scree / talus** at cliff feet | every cliff | built (paint and rock piles) |
| 8 | **Trails and roads** between settlements | neutral building clusters, shelters | built; bridges where a trail wades are PLANNED |
| 9 | **Settlement dressing** — fences, crates, lamps | the meadow ring | TODO: not built |
| 10 | **Pond rims** — lithium crust, evaporation stains | lithium ponds | TODO: not built; ties to resource readability, so worth an art-direction decision first |
| 11 | **Map-edge framing** — a drop or haze beyond the play area | the play rectangle | TODO: not built |

## Known gaps

- TODO: a plan takes about 1.6 s in GDScript on a 274-cell map (mostly the chamfer transforms
  and trail A*), paid at every load and on every editor open (`Map.decorate_in_editor` turns
  the editor run off). Not measured against a budget.
- TODO: the editor does not re-derive after a brush stroke — the decoration is as of the last
  open.
- TODO: removing a structure does not bring back the props it cleared.
- TODO: tall props on impassable ground can hide a unit standing behind them at the game's
  camera angle; whether they want the see-through silhouette treatment is undecided.
- TODO: the minimap does not draw trails or meadows.
