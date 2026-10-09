---
title: Incremental navmesh
type: system-note
---

# Incremental navmesh

*Design note for [Dissent Horizon](../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

A structure placed or destroyed rebuilds only the navmesh around it, not the whole map.
`NavManager` cuts the base mesh and every [size-class](agent-size-classes.md) mesh into
`CHUNK_SIZE_CELLS`-square chunks, one navigation region each, all on the one shared navigation
map. A `cells_changed` rebuilds only the chunks the change can reach. `TerrainGrid` likewise
recomputes its distance and clearance fields only around the change, which is why those fields
saturate at `FIELD_CAP_CELLS`.

Built 2026-09-26. The code carries the mechanism. This note keeps what the code cannot: why
the chunk grids are staggered, what was measured, and what was turned down.

## Why the chunk grids are staggered

**Each mesh's chunk grid starts at a different offset, so no two meshes share a chunk border
line.** `tests/test_NavChunks.gd` fails if they are aligned.

Godot joins polygons inside a region when the region is built. At map level it merges only
a region's *external* edges, matched by exact vertex position. It links an edge only when
exactly two polygons claim it; more than two is logged as *"More than 2 edges tried to occupy
the same map rasterization space"*, and the extra claimants go unlinked.

Chunking makes every chunk border an external edge. Across open ground the base mesh and
every class mesh have the same uninset vertices, so with aligned grids four regions claim every
border edge. On the skirmish map that lost up to 71% of paths. The navigation-layer bits do not
help: they filter the search, not the merge.

Chunks are joined by that exact-edge merge, never by edge connections: a corner on a chunk
border is computed from the same four cells in both chunks, so it comes out bit-identical in
each.

## Measured

Skirmish map, 261×261 cells, 30,791 passable, on the M3 Pro.

| | Before | After |
|---|---|---|
| a placement or removal (fields + affected chunks) | ~800 ms | **3–4 ms** |
| the first, whole-map build | ~750 ms | ~300 ms |
| `TerrainGrid` field recompute after a change | 26–31 ms, whole map | inside the 3–4 ms |
| paths lost vs the monolithic mesh (300 pairs × 3 classes) | — | **0 of 569**, mean length ratio 1.0001, worst 1.012 |
| "more than 2 edges" warnings per build | 1 | 0 |

An incremental rebuild was checked bit-for-bit against a from-scratch build of the same grid,
fields and every chunk's vertices included, at chunk borders of both the base and a class grid.

**Chunk size.** Measured 16, 32 and 64: work is proportional to the chunks a change touches,
and a 16-cell chunk touches the fewest cells. The ~670 regions this makes cost nothing
measurable in path queries.

**Region labels (`TerrainGrid._component`) stay global and lazy.** Only bot placement reads
them, and relabelling costs ~10 ms, once, on the first placement query after a change.
**TODO — that relabel is now the largest single bot cost left:** the economy's first build-spot
search after a structure change runs 12–13 ms in one piece, which the scheduler cannot split
([ai/think-scheduling](../ai/think-scheduling.md)). A local relabel around the change would
remove it.

## Rejected

- **REJECTED — a packed rewrite of the monolithic build, without chunks.** ~3× faster, but
  ~240 ms still freezes the game, and the cost grows with map area rather than with the change.
- **REJECTED — building the monolithic mesh on a worker thread.** It hides the cost rather
  than removing it, and widens the window in which a new footprint is still walkable, the race
  `NavManager.await_excluded` exists to wait out.
- **REJECTED — one navigation map per size class.** It avoids the merge collision too, but
  `NavigationAgent3D` does pathing and RVO avoidance on one map, so units of different sizes
  would stop avoiding each other.
- **Merging cells into larger polygons is still out** — a separate rule about path directness,
  recorded after `NavManager._build_chunk`. Chunks keep one quad per cell.

## The minimap rides along without a dirty rectangle

The minimap still re-derives its whole map layer on every `cells_changed`, and that is now
cheap enough not to need the same dirty rectangle: its per-cell inputs come from the grid's
native impassable mask and `TerrainData`'s memoized in-play mask
([authoring/native-code](../authoring/native-code.md)). Measured 2026-10-09, the 300–450 ms
stall every structure placement or loss used to cost is gone.
