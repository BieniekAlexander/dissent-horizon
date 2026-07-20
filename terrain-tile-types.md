# Terrain Tile-Type System — Design & Implementation Plan

## Goal

Replace the current terrain representation with a **tile-type-driven** model, authored and
generated as a single resource.

- **Unify the two authored inputs.** Today terrain is split across `Map.height_map` (a
  `HeightMapShape3D` `.tres`) and `Map.blocked_cells` (an inline `Array[Vector2i]`). Collapse
  both into one `TerrainData` resource.
- **Tile types govern passability (and, later, textures).** Each cell has a *type*; the type
  decides whether the cell is permanently passable/buildable. Textures are deferred but the
  model reserves room for them.
- **Procedural-generation-first.** Per-cell type is a byte index; generators just write bytes.
- **Open (AoE2-style) topology, not SC2 plateaus.** This is a *generator* concern — the model
  supports any topology; generators decide how partitioned a map is.
- **Keep a distinct cliff/steepness layer.** Height-derived impassability stays its own layer so
  a future "cliff-scaling" movement class can path over cliffs while still respecting water,
  forest, and buildings.

## Current state (what we're replacing)

Two authored inputs feed the terrain:

- `Map.height_map: HeightMapShape3D` — corner heights (`map_data`, size `W*D`). Read **directly** by:
  - `Map.grid_to_world` / `terrain_height_at` / `world_to_grid` / `footprint_origin`
  - `TerrainGrid` (steep/flat/corner-height, via `height_map.map_data`)
  - `NavManager._build_mesh` / `_sample_height` / `_sample_navigable_world_point`
  - `HeightmapMeshGenerator._build_mesh` (`shape.map_data`)
  - **the cursor-picking collider**: `Map._terrain_collision_shape.shape = height_map`
- `Map.blocked_cells: Array[Vector2i]` — authored no-go overlay. Converted to a cell mask
  (`_blocked_cells_to_mask`) and fed to `TerrainGrid.set_blocked_mask` at `_ready`.

`TerrainGrid` already holds passability as **three independent bits** per cell in `_cell_state`:

| Bit         | Source                              | Nature             |
|-------------|-------------------------------------|--------------------|
| `_STEEP`    | corner-height spread > `MAX_SLOPE_DIFF` | permanent, **cliff** |
| `_BUILDING` | structure placement                 | temporary          |
| `_BLOCKED`  | `blocked_cells`                     | permanent, no-go   |

Generators today: `HeightmapGenerator.generate() -> PackedFloat32Array` (heights only);
`BlockMaskGenerator.generate() -> PackedByteArray` (boolean mask).

## New data model

### `TileType` (Resource) — one entry in the catalog

```gdscript
class_name TileType extends Resource
@export var name: String = "Open"
@export var passable: bool = true      # permanent passability (water/forest/cliff-type = false)
@export var buildable: bool = true
# --- reserved for later, not built now ---
# @export var texture: Texture2D       # real per-type texturing (Stage 4)
# @export var move_cost: float = 1.0
# @export var harvestable: bool = false  # e.g. a forest that converts to Open when cleared
```

### Debug visualization — derived tri-state (not a per-type color)

The in-editor debug coloring is a function of each cell's **computed** state, not an authored
per-type color (because "buildable vs merely passable" depends on *flatness*, a height property):

- **red** — not passable: `type.passable == false` (water/forest/no-go) **or** cell is too steep (`_STEEP`)
- **blue** — buildable: passable **and** `type.buildable` **and** `TerrainGrid.is_flat(cell)`
- **green** — passable but not buildable (e.g. an Open-typed cell on a slope)

Wired onto the **per-cell editor overlay** (the repointed BlockPins — one marker per cell), **not**
the gameplay terrain mesh: `HeightmapMeshGenerator` deliberately *omits* impassable cells (they
render as holes — the same behavior the camera/diamond-mask work depends on), so an impassable cell
must show as a red *overlay marker*, not a red quad. The overlay doubles as the Stage-1 authoring
surface and visually verifies the converter. Real per-type textures/tints are a separate concern
(Stage 4).

### `TerrainTileCatalog` (Resource) — the standalone palette

The catalog is the lookup that turns a per-cell **byte** into a `TileType`. Stored as its own
`.tres` (`resources/terrain/tile_catalog.tres`) so types can be added/tuned as data without code
changes.

```gdscript
class_name TerrainTileCatalog extends Resource
@export var types: Array[TileType] = []   # byte index -> TileType; index 0 = default "Open"
func passable(i: int) -> bool:  return i < types.size() and types[i].passable
func buildable(i: int) -> bool: return i < types.size() and types[i].buildable
func count() -> int:            return types.size()
```

Initial contents (only `passable` matters until textures land): `Open(0)` passable+buildable,
`Water(1)`, `Forest(2)`, `Cliff(3)`, `NoGo(4)` — all impassable.

### `TerrainData` (Resource) — the single authored source of truth

```gdscript
class_name TerrainData extends Resource
@export var dimensions: Vector2i = Vector2i(120, 120)  # W x D corners
@export var heights: PackedFloat32Array = PackedFloat32Array()   # size W*D,     per-corner
@export var tile_types: PackedByteArray = PackedByteArray()      # size (W-1)*(D-1), per-cell
@export var catalog: TerrainTileCatalog

func map_width() -> int:  return dimensions.x
func map_depth() -> int:  return dimensions.y
func grid_width() -> int: return dimensions.x - 1
func grid_depth() -> int: return dimensions.y - 1

# Derived artifacts (see migration insight below)
func to_height_shape() -> HeightMapShape3D          # heights -> HeightMapShape3D.map_data
func blocked_mask() -> PackedByteArray              # 1 where catalog.passable(type)==false
```

Note the two layers sit on **different grids** — heights on corners (`W*D`), types on cells
(`(W-1)*(D-1)`) — which is the standard heightfield offset and is fine.

## Key migration insight — `HeightMapShape3D` becomes a *generated intermediate*

`HeightMapShape3D` is read in many places and is the picking collider. Rather than repoint every
reader onto `TerrainData` at once (wide, risky), keep `HeightMapShape3D` as a **derived artifact
of `TerrainData`** — the same "generate from a source" pattern the visual mesh and navmesh already
use. `Map` derives, from `terrain_data`:

1. a `HeightMapShape3D` (`heights` → `map_data`) — used as the picking collider **and** read by
   `TerrainGrid` / `NavManager` / `HeightmapMeshGenerator` exactly as today, and
2. a blocked mask (`tile_types` where the type is impassable) fed to `TerrainGrid`'s `_BLOCKED` bit.

This collapses the two authored inputs into one `TerrainData`, is **behavior-identical**, and lets
readers migrate onto `TerrainData` directly later if desired (keeping `HeightMapShape3D` purely as a
generated picking collider is a fine long-term end state — units don't collide with it).

## Passability mapping

- `_BLOCKED` ← `catalog.passable(tile_types[cell]) == false` (permanent: water/forest/cliff-type/no-go)
- `_STEEP` ← unchanged (heights + `MAX_SLOPE_DIFF`) — **the cliff layer, kept distinct**. A future
  cliff-scaler is a movement class whose navmesh predicate ignores `_STEEP` but still respects
  `_BLOCKED` and `_BUILDING`; this composes with the existing `NavAgentClass` per-class navmesh system.
- `_BUILDING` ← unchanged (temporary)

## Stages

### Stage 1 — resources + derivation (behavior-preserving) — ✅ DONE (2026-07-10)

Implemented: `TileType` / `TerrainTileCatalog` / `TerrainData`
(`scripts/maps/terrain/`), `resources/terrain/tile_catalog.tres` (Open/Water/Forest/Cliff/NoGo),
`resources/terrain/s1_terrain.tres`, `Map.terrain_data` (derives `height_map` + `_BLOCKED` mask;
`_validate_property` stops the derived heightmap being serialized), `blocked_cells` cut, BlockPin +
`_spawn_block_pins` + `set_cell_blocked` + the mirror tool + the mesh generator's hole test all
repointed onto `terrain_data`, tri-state pin colouring. Verified headless: conversion lossless
(547 NoGo, heights identical), s1 boots with a derived 80×50 heightmap and an identical navmesh
(2854 polys = passable cells). Terrain GUT tests green (21/21). Editor behaviour verified in-editor:
BlockPin tri-state colours + blocked-toggle hole punch/fill, HeightPin edits persisting to terrain_data
across a reload, correct in-game render/picking.

Original task list, for reference:

1. Add `TileType`, `TerrainTileCatalog`, `TerrainData` (`class_name`s; run
   `godot --headless --editor --quit` once so GUT/registry pick them up).
2. Author `resources/terrain/tile_catalog.tres` with the initial types above.
3. `Map`: add `@export var terrain_data: TerrainData`. On `_ready` (runtime) and on inspector
   assignment (editor), derive `height_map` from `terrain_data.to_height_shape()`, set the picking
   collider to it, and feed `terrain_grid.set_blocked_mask(terrain_data.blocked_mask())`.
4. **Converter** (EditorScript / inspector button): build a `TerrainData` from a Map's current
   `height_map` + `blocked_cells` (`heights ← map_data`; `tile_types` all `0` except `blocked_cells`
   → `NoGo` index). Run it on `s1`, save `resources/terrain/s1_terrain.tres`, assign to
   `Map.terrain_data`.
5. **Cut `blocked_cells` once `s1` is converted** (decision #2). Remove the `blocked_cells` export,
   `_blocked_cells_to_mask`, `_mirror_blocked_cells`, and the `blocked_cells` branch of `_ready`.
   **Repoint `BlockPin` / `_spawn_block_pins`** to read/write `TerrainData.tile_types` as an
   Open(0)↔NoGo toggle (a minimal change — a BlockPin already toggles one cell), so no-go authoring
   survives until the Stage-3 brush generalizes it to full multi-type painting.
6. **Debug tri-state coloring** on the per-cell overlay (the repointed BlockPins), red/blue/green per
   the rule above, driven off the derived `TerrainGrid` state — not the gameplay mesh (which omits
   impassable cells).

**Verify (headless — this stage IS checkable):** derived `map_data` equals the original;
`blocked_mask()` reproduces the old `blocked_cells` set; navmesh polygon count and passable-cell
count are identical to pre-change on `s1`.

### Stage 2 — generators emit `TerrainData` + open topology

1. A `TerrainGenerator` producing a full `TerrainData`: a **height pass** (existing
   `HeightmapGenerator` subclasses) + a **tile-type pass** (`BlockMaskGenerator` reworked to paint
   `Water`/`Forest` cells instead of a boolean mask, staying connectivity-safe).
2. Retune/replace `graph_plateau` for open rolling terrain (or gentle noise) so maps aren't
   over-partitioned into plateaus with thin corridors; `_STEEP` remains for occasional cliffs.
3. Point `HeightmapGeneratorTool` / the heightmap workbench at `TerrainData` output.

### Stage 3 — brush authoring (replaces pins) — ✅ DONE (2026-07-10)

Built `addons/terrain_brush/` (`EditorPlugin`): spatial-toolbar with a **Mode** (Paint / Raise / Lower
/ Smooth / Set), a tile-type picker, a radius, a strength, and a target-height. `_forward_3d_gui_input`
marches the editor camera ray onto the terrain surface to pick a cell, then click-drag paints:
- **Paint** → per-cell `terrain_data.tile_types` (mesh holes update live, overlay refresh on release);
- **Raise / Lower / Smooth / Set** → per-corner `terrain_data.heights` (live in-place mesh reshape).
Yellow ring preview, one undo action per stroke (swaps the edited layer). Height edits are **clamped to
[0, 5] and snapped to 0.5** steps; **Set** flattens corners in-radius to a chosen height.

**Pins fully removed (2026-07-10):** `height_pin.gd` / `block_pin.gd` deleted, the `heightmap_editor`
gizmo addon removed, all `Map` pin machinery excised (`generate_editor_pins`, `_spawn_*_pins`,
`set_cell_blocked`, `_on_pin_height_changed`, `_on_height_shape_changed`, `_sync_height_pins`, …), the
`scene_visibility_tools` pin buttons dropped, and saved pin nodes/ext_resources stripped from 7 scenes
(s1 alone: 7 873 nodes). **Trade-off (user-accepted):** the tri-state colour overlay is gone (it lived on
BlockPins); brush feedback is now mesh holes + live topography. A future per-cell mesh vertex-colour debug
mode could restore blue/green. Verified: all 7 scenes load, s1 boots identical (2854 navmesh polys),
terrain GUT 26/26. The mirror tool now operates directly on `terrain_data` (heights + tile_types).

### Stage 4 (future) — textures

Per-type textures / mesh shading, `TileType.texture` + blend rules, procedural texture pass. Until
then the mesh keeps the current checkerboard shader (optionally tinted per-type via
`TileType.color`).

## Migration surface (currently coupled to `height_map` / `blocked_cells`)

| Consumer | Stage 1 | Later |
|---|---|---|
| `Map` coord helpers, `TerrainGrid` steep/flat/corner, `NavManager`, `HeightmapMeshGenerator`, picking collider | read the **derived** `HeightMapShape3D` — **no change** | optionally read `TerrainData` directly |
| `HeightPin` / `generate_editor_pins` | still work vs derived shape | replaced by brushes (Stage 3) |
| `BlockPin` / `_spawn_block_pins` | **repointed** to `TerrainData.tile_types` (Open↔NoGo) | subsumed by the multi-type brush (Stage 3) |
| Mirror tool (`Map._mirror_heightmap` / `_mirror_blocked_cells`) | keep working vs derived shape | repoint to mirror `TerrainData` layers (Stage 3) |
| `HeightmapGeneratorTool` / workbench | unchanged | emit `TerrainData` (Stage 2) |

## Resolved decisions

1. **Debug coloring:** yes — a **derived tri-state** (red = impassable/steep, blue = buildable,
   green = passable-not-buildable), wired in `HeightmapMeshGenerator` in Stage 1 (see *Debug
   visualization* above). Not a per-type authored color.
2. **`blocked_cells`:** **hard-cut in Stage 1** once `s1` is converted (no deprecated fallback);
   `BlockPin` is repointed to `TerrainData` so authoring continuity is preserved.
3. **Resource locations:** `resources/terrain/tile_catalog.tres` and
   `resources/terrain/<map>_terrain.tres`.
