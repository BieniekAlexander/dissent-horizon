---
title: Map and terrain grid
type: system-note
---

# Map and terrain grid

*Design note for [Dissent Horizon](../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

## `Map` (`@tool`, `scripts/maps/map.gd`)


The scene node that owns terrain and navigation. Key exports:
- `@export var terrain_data: TerrainData` — **single source of truth**: per-corner `heights` + a per-cell `tile_types` layer (byte indices into a `TerrainTileCatalog`). See `../terrain-and-navigation/tile-types.md`.
- `@export var height_map: HeightMapShape3D` — **derived** from `terrain_data` (`TerrainData.to_height_shape()`) at load; read by `TerrainGrid` / `NavManager` / the mesh generator and used as the cursor-picking collider. `_validate_property` keeps the derived value out of the saved scene. (Un-migrated maps may still assign it directly instead of `terrain_data`.)
- `const CELL_SIZE: float = 1.0` — world-space side of one terrain cell; encoded as Map's own scale in the scene

Key methods:
- `grid_to_world(cell: Vector2i) -> Vector3` — bilinearly samples corner heights for Y
- `world_to_grid(world_xz: Vector2) -> Vector2i` — exact inverse
- `terrain_height_at(world_xz: Vector2) -> float` — bilinear interpolation for continuous height

`Map` maintains `cell_grid: Array` (2D, indexed by grid coords, null = unoccupied, non-null = Commandable) for O(1) structure lookups, and `structure_cell_map: Dictionary` (Commandable → Array[Vector2i]).

## The corner grid is DERIVED from the play size, and is always square

`TerrainData.dimensions` is not authored. `play_size` is the map, and `derive_dimensions`
computes the smallest corner grid that holds it.

A grid of *a* x *b* CELLS maps, in screen (s, t) space, to the diamond bounded by
`0 <= (s+t)/2 <= a` and `0 <= (s-t)/2 <= b`. Testing the play rectangle's four corners
against that reduces — for **all four** — to the same pair of conditions:

```
play_size.x + play_size.y <= a    AND    play_size.x + play_size.y <= b
```

So the minimal enclosing grid is always **square**, with side `play_size.x + play_size.y`,
whatever the play rectangle's aspect ratio: a 50x60 play area and a 60x50 one need the
identical grid. That is why `dimensions` carries no information of its own — there is no
shape left to choose. Add the `+1` that `W = cells + 1` costs and the grid is fixed.

**There is deliberately no padding knob.** Cells outside the play rectangle are not backdrop
scenery: `HeightmapMeshGenerator` emits no geometry for them at all (they stay gaps, so the
play-area edge reads against the background), the brush refuses to paint them, and fog
pre-clears them. Grid beyond the play area is invisible, unwalkable, unauthorable storage.

## `TerrainGrid` (`scripts/maps/terrain/terrain_grid.gd`)


Derives the navigable cell grid from the heightmap. A `HeightMapShape3D` with `map_width` W and `map_depth` D yields **(W−1) × (D−1) navigable cells** (one quad per adjacent corner pair). Passability is one `_cell_state: PackedByteArray` (a per-cell bitmask of impassability *reasons*); a cell is passable iff its byte is `0`, so the check is a single byte read. Each source flips only its own bit:
- `_STEEP` — corner-height spread > `MAX_SLOPE_DIFF`, derived from the lowest camera pitch (the cliff layer; precomputed at startup)
- `_BUILDING` — a structure occupies the cell (`place_building` / `remove_building`; `_building_footprints` maps each structure → its cells)
- `_BLOCKED` — the cell is out of play (past the play rectangle, or void where the mesh bake found no ground), fed from `terrain_data.blocked_mask()` via `Map.set_blocked_mask`. Ground material never blocks — [map-composition](map-composition.md)

Emits `cells_changed(cells: Array)` whenever passability changes.
