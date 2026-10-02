---
title: Map composition
type: system-note
---

# Map composition — what a map is made of

*Design note for [Dissent Horizon](../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

It fixes the vocabulary and the engine model for the map features, so that
[map-generation.md](map-generation.md) has something concrete to place. Water and the lithium
pond are owned by [water-bodies.md](water-bodies.md).

> **REJECTED — water as a tile type.** A painted `Water` type can contradict the geometry (a
> lake on a hilltop) and a depth rule cannot, so water became a level over a sculpted basin.
> Having each structure name the tile types it accepts went with it: the HOST grants build
> permission.

---

## The features

A map is built out of five kinds of thing, and nothing else. Anything a generator wants to put
on the ground has to be one of these or a new entry here.

| Feature | What it is |
|---|---|
| **Extraction site** | `nt_extractionSite` — infinite lithium. Occupies its cells against other builders but is **walkable** (§Occupancy and obstruction) |
| **Extractor** | `nt_extractor` — the only structure buildable on a site or a pond. On a site it is what **obstructs** the site's cells |
| **Lithium pond** | a `WaterBody` with a finite budget — [water-bodies.md](water-bodies.md) |
| **Building** | the `nt_building_*` family — neutral, garrisonable, of differing footprints (2×2 to 8×5); generation places them in **clusters** |
| **Shelter** | `nt_shelter` — 3×3, produces Terrestrials |

**Energy has exactly one collector.** Both the site and the pond are worked by the same
`Extractor` structure; they differ only in the reservoir behind them (infinite vs finite) and in
the rate. That is deliberate — a second collector type would be a *sibling* of the abstraction
rather than an *instance* of it (`~/.claude/CLAUDE.md` §1.3).

**The site's footprint is defined to equal the extractor's.** That is what lets
`EnergyExtractor.valid_placement` demand a *concentric* host rather than a merely-overlapping
one — there is exactly one valid position per host, so the ghost the player aims, the blueprint,
and the finished extractor all stand in the same cells. A site sized differently from its
extractor breaks that check, not just the looks. TODO: both are 2×2 today; a resize has to move
both.

---

## Occupancy and obstruction

A fixture's cells carry two facts that are set independently:

- **Occupancy** — `Map.cell_grid` names the fixture, so nothing else may be placed there.
- **Obstruction** — the terrain grid's `_BUILDING` bit, so the cells leave the navmesh. Only a
  fixture whose `Structure.is_obstruction` is true sets it.

The extraction site occupies without obstructing: an extractor is the only thing that can be
built over it, and units walk across it until one is. The extractor built over a site registers
the site's footprint as its own and obstructs it, while `cell_grid` keeps naming the site — one
occupant per cell — so removing the extractor leaves the site where it was.

A registered fixture carries no `MOVEMENT_OBSTRUCTION` layer on its body, whether it obstructs or
not: an obstruction is avoided through the navmesh, and a walkable fixture must not be bumped into.

---

## A dry chasm is reachable by air; a deep one is not reachable at all

The two obstructions look alike from above and behave differently, deliberately:

- **A dry chasm floor is passable.** It becomes a navmesh component disjoint from the rest of the
  map, and that is **allowed, not a bug** — an air transport can set units down in it. Nothing
  prunes unreachable components.
- **Deep water obstructs completely.** A cell submerged past `WADE_DEPTH` is impassable, so no
  navmesh is generated under a lake at all and the disjoint-island case never arises there.

A ground order into a disjoint component is left exactly as clicked and the navigation agent walks
as close as it can — see [navigation-and-pathing.md](navigation-and-pathing.md) §An unreachable
destination is left alone. Correcting the destination would draw the player a map of where the
unreachable region begins.

---

## What survives of the tile-type layer: the art, and only the art

The per-cell byte layer is **ground material** and nothing else. `TileType` carries a name, a
map colour and a texture; the catalog is Grass, Dirt, Sand, Rock and Lithium bed, all walkable,
all buildable. The brush paints materials; a material never makes ground unwalkable.

**Impassability is always something you can see.** If an area is unwalkable, it is because the
terrain was sculpted into a chasm, a ridge or a lake, because the mesh bake found no ground
there, or because it is past the edge of play — and the player can read each of those from the
geometry. A fence with no visible fence is ruled out.

**A cell with no ground is out of play.** A mesh-authored surface need not cover its grid (a
disc-shaped island), and the bake records the uncovered cells in `TerrainData.void_cells`. "In
play" means inside the play rectangle AND not void, so a void cell is blocked and drawn as a gap
exactly like the corners of the grid past the play rectangle. The void layer is the bake's output
only: nothing paints it, and resizing the map drops it until the next bake.

The mesh generator's fates for a cell:

| Cell | Fate |
|---|---|
| out of play (void included) | omitted — a literal gap, so the playable area reads against the background |
| submerged (any depth) | drawn normally — this is the bed under the water plane |
| `_STEEP` | solid black — a hole here would show the background through a cliff |
| anything else | drawn with its ground material |

TODO: `tile-types.md` Stage 4 (per-type textures) is unaffected in mechanism — the
`Texture2DArray` layer index in vertex `COLOR.a` still works — and its type list is now the
material list.

## The basin still has an unbuildable rim

A pond is a flat floor with sloped sides, and both halves matter:

- **The floor must be flat.** `is_flat` demands all four corner heights *identical*, so an extractor
  can only stand on a level basin floor. Generation sinks a pond as a flat pan, not a smooth bowl.
- **The rim is passable but not buildable — and that is the GENERATOR's job to guarantee.**
  A rim whose corner spread is exactly `MAX_SLOPE_DIFF` is not `_STEEP` (units walk in and out)
  and not `is_flat` (nothing is built there), which is why the limit is exact in float32
  (map-generation.md §Parameters). **A sink steeper than `MAX_SLOPE_DIFF` per cell-ring
  makes the rim a cliff instead**, which walls the pond off; a deeper basin must be spread over
  more rings. That is the knob separating a wadeable pond from a lake.

  **This does not fall out of the authoring tools.** Terrain heights are CONTINUOUS floats clamped
  to `[MIN_HEIGHT, MAX_HEIGHT]` = `[0, 32]`; the brush's `HEIGHT_STEP` (0.05) is SpinBox
  granularity only, and `_clamp_height` does no snapping at all — quantization was deliberately
  removed so a feathered brush can make a slope. So a hand-sculpted pond rim lands on an arbitrary
  spread and is wadeable only by luck. The exact-0.5 rim is a value the generator WRITES, and
  hand-authored ponds need a brush mode that can hit it (there is none today).

  TODO: no brush mode produces an exact rim spread. Either the generator is the only way to author
  a pond, or the brush needs a quantizing Set mode. Not decided.

---

## What comes next

Generation — [map-generation.md](map-generation.md).
