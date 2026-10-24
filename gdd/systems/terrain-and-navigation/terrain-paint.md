---
title: Terrain paint
type: system-note
---

# Terrain paint

*Design note for [Dissent Horizon](../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md
carries only the pointer.* Scoped 2026-10-24; nothing here is built yet unless marked.

**Painting terrain surfaces with a brush, finer than the cell grid, in textured layers that
blend.** The visual reference is Halo Wars 2's ground: transitions that wander freely instead of
following cell edges, layered materials (rock, soil, grass) that mix with crisp, broken edges,
and hard-surface ground (plating, roads, scorch) laid over it. The art itself stays stylized
([art-direction](../ux/aesthetics/art-direction.md)); what is adopted is the *structure* of the
look, not its realism.

## Decisions

- **Paint is visual only, and replaces tile types.** Decided 2026-10-24 (Alex): tile types will
  never carry movement cost or harvestable ground, so `TerrainData.tile_types` and the tile
  catalog are deprecated once paint lands. Nothing reads paint for gameplay. — REJECTED:
  keeping `tile_types` as a coarse gameplay layer beside paint (nothing would read it).
- **Paint is a PRIMARY layer, saved with the map.** It is authored, so it is stored, unlike
  pass 7's ground overlay ([visual-facets](visual-facets.md)), which stays derived and is
  composed on top. Neither is derived from the other — CLAUDE.md §Regenerating data.
- **Readability does not constrain the palette.** Decided 2026-10-24 (Alex): resources read only
  as fixtures and shallow water, so no paint layer can imply one; any layer may be painted
  anywhere. Impassability is unaffected either way: the shader draws impassable rock and the
  ink line over paint unconditionally, so passability stays binary
  ([terrain-readability](../ux/aesthetics/terrain-readability.md)).
- **Generated maps paint too.** Decided 2026-10-24 (Alex): the generator already lays dirt
  trails, and it should write the paint layer like any author. TODO: revisit what the
  generator paints, and how (T-117).

## Data

- **Weights, not indices.** Each paint layer has a weight per texel; a texel's weights sum to 1.
  Four layers pack into one RGBA8 image.
- **Resolution: 4 texels per cell** (proposed). At the largest generated size (play size 120,
  241 × 241 cells) that is 964 × 964 texels, 3.5 MB per image in memory; play size 200 is
  1604 × 1604, 9.8 MB.
- **Stored as PNG beside the `TerrainData` `.tres`**, not inside it, so a repaint does not
  rewrite a multi-megabyte text resource and git sees a binary file. The `.tres` points at it.
  The bake-must-save trap ([mesh-baked-terrain](mesh-baked-terrain.md) §The bake must SAVE)
  applies: a paint stroke edits an image the scene save does not write, so saving the paint is
  the tool's job and must be verified the same way.

### Layer count

TODO: decide (Alex leans to whichever is cheaper). The options, mocked up by
`tools/terrain_paint_bench/layer_mockup.py` (illustrative, not engine output):

| Layers | Weight images | Per pixel | What it buys |
|---|---|---|---|
| 4 | 1 | 1 weight fetch, up to 4 material samples | ground, path, rock, plating — enough for the HW2 structure |
| 8 | 2 | 2 weight fetches, up to 8 samples (or the top 4 selected) | finer variety: moss, gravel verges, sand, scorch |
| 4 per map from a catalog | 1 | as 4 | 4 at a time, but each map picks its 4 from a larger catalog, so biomes differ |

The third row suits the biome direction ([world-building](../../world-building.md): three
starter biomes, a per-planet palette later) at the price of the first: a map's own layer count
is what costs, not the catalog's size. Scorch and similar marks may come from decals instead
(Phase 6), which would reduce the case for 8.

## Phases

| # | Work | Effort |
|---|---|---|
| 1 | **Weight layer** in `TerrainData` (PNG beside the resource), filled from `tile_types` once so existing maps keep their look; the generator writes it | medium |
| 2 | **Brush**: Paint writes weights — strength, falloff (the existing feather), erase, eyedropper; footprint in world units; one undo per stroke; live update re-uploads the weight texture only, never the mesh | small–medium |
| 3 | **Shader**: sample weights, height-blend up to 4 materials per pixel (planar XZ projection; steep ground is rock regardless); impassable rock and the ink line drawn last | medium |
| 4 | **Layer art**: stylized tiling textures; placeholders unblock everything else | high, ongoing |
| 5 | **Integration**: pass-7 overlay composed over paint; minimap reads the dominant layer; `tile_types` and the catalog removed | small |
| 6 | **Decals** (optional): projected plating, road markings, scorch — most of the built-up look ([art-direction](../ux/aesthetics/art-direction.md) pillar 3) | medium–high |

Suggested order: 1–3 on one test map with placeholder textures, reviewed before the generator
and the remaining maps move over.

## Large-map measurements (2026-10-24)

`tools/terrain_paint_bench/terrain_paint_bench.gd`, median of 5, synthetic maps, Godot 4.7 on
a 2-core Linux VM with a software renderer (llvmpipe). The mesh rebuild is CPU work and should
be broadly comparable on a desktop; texture uploads on a real GPU should be cheaper still.

| Per mouse-motion step | play 79 (s1) | play 120 (largest generated) | play 200 |
|---|---|---|---|
| **Current** Paint: stamp + full mesh rebuild | 163 ms | 400 ms | 982 ms |
| … of which `cell_data_texture()` | 8 ms | 17 ms | 49 ms |
| Proposed: stamp, radius 4 cells (GDScript) | 0.5 ms | 0.5 ms | 0.5 ms |
| Proposed: stamp, radius 16 cells (GDScript) | 7.9 ms | 7.7 ms | 7.7 ms |
| Proposed: weight texture upload | 0.1 ms | 0.3 ms | 2.4 ms |

- **The current brush is already too slow on large maps** (T-116): it rebuilds the whole mesh on
  every cell the cursor crosses, so painting a generated map stutters at 2–3 steps a second.
  The proposed layer fixes this by construction, because painting stops touching the mesh.
- The stamp cost tracks the brush area, not the map: a broad 16-cell brush in GDScript is
  ~8 ms. Fine for an editor; a native stamp is an option if it is ever not.
- The undo snapshot (`duplicate`) is copy-on-write and measured as free; its real cost lands on
  the first write of a stroke and is inside the stamp numbers.
- TODO: a painted map's PNG size is not measured — the bench's uniform image compresses to
  ~20 KB, which says nothing about a real painting.

## Risks

- TODO: decoration does not re-derive after a brush stroke ([visual-facets](visual-facets.md)
  §Known gaps); with paint under it, a stale overlay is more visible.
- Memory at play size 200: 10 MB per weight image, 20 MB at 8 layers. Fine on desktop; worth a
  look if a smaller target ever matters.
