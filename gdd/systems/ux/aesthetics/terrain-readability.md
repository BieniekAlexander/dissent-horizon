---
title: Terrain readability
type: system-note
---

# Terrain readability

*Design note for [Dissent Horizon](../../../../CLAUDE.md).* How the terrain shader makes height
and passability legible at gameplay zoom. The cues are the settled part; every colour and weight
is a placeholder (Alex, 2026-10-01: the visual language is revisited later, and is meant to be
illustrative rather than realistic). Shading lives in `terrain_common.gdshaderinc`, shared by
both terrain renderers; its per-map inputs are pushed by `TerrainShading`.

| Question a player asks | Cue |
|---|---|
| Can a unit go here? | **Binary.** Impassable cells are rock; an ink line sits on the passable side of every passability boundary, exactly where the navmesh's steep test changes. Nothing soft is allowed to blur it |
| Which ground is higher? | hypsometric tint (low ground darker, high ground lighter); lighting from a normal derived from the height FIELD rather than the per-cell quads, so grades read as slopes, not stairs |
| Is this ground a slope? | **banks** — graded walkable ground is darkened in VALUE as its gradient rises, keeping the hue of the ground around it, with a noisy edge: the RTS ramp convention, where a ramp is the same floor lit differently. A hue shift was tried first (2026-10-01): earth-brown read as a trail, and olive read as a different material |
| Which way does this slope fall? | **exaggerated relief lighting** — the lit normal's tilt on walkable ground is overstated several times, as RTS terrain overstates its hillshade: the sunward side of a grade lifts and the far side falls into shade. Plus cavity shading (below) for slopes facing along the sun, which side light cannot separate |
| Where does one level end? | a thin contour line every terrace step, offset so each step carries exactly one |
| Is this ground tilted at all? | **grain** — a fine stipple of grass clumps in both albedo and the lit normal, so the same bumps catch the sun differently once the ground under them tilts (2026-10-02: the smooth fill gave a slope nothing to show itself with) |
| Is this a pit or a rise? | cavity shading — ground below its local mean (a coarse mip of the height texture) darkens slightly, ground above it brightens |
| Is this the same field everywhere? | two-octave world-space noise and pass-7 ground paint ([visual-facets](../../terrain-and-navigation/visual-facets.md)) |

**A cliff's edge is drawn smooth; passability stays per cell.** Two things made diagonal
cliffs read as staircases, and both are drawing. Alex chose the fully smoothed look over
rounded squares (2026-10-21):

- *The painted edge.* Rock and the ink line came from the per-cell steep flag, so every cell
  showed its square. `th_rock_sd` now treats each flag as a sample at its cell centre and draws
  the contour between samples: a straight edge stays on the cell boundary the navmesh cuts
  along, and a 45-degree staircase becomes a straight diagonal through the cell-edge midpoints.
  `rock_edge_smoothing` blends back toward the plain squares with rounded corners — the
  calibration of how far the drawn edge may stray from the grid (a lone corner strays by up to a
  quarter cell at full smoothing).
- *The geometry.* Every cell was split along the same diagonal, so a diagonal cliff stepped in
  3D however it was painted. `HeightmapMeshGenerator` now splits each cell along its flatter
  diagonal; the cells stay axis-aligned squares. TODO: the physics `HeightMapShape3D` still uses
  the fixed split, so collision and the drawn surface differ inside steep cells — which units
  never stand in, and terrain height for units is bilinear anyway; nothing known depends on it.

REJECTED — the navmesh following the smooth edge (Alex, 2026-10-21): it stays one quad per
walkable cell. The drawn edge differs from where units stop by at most a quarter cell at a
corner, mostly covered by the units' own radius. Trimming walkable corners would be cheap, but
growing walkable area into rock cells hits the T-junction and collinear-vertex failure
`NavManager._build_chunk` documents, and either way the navmesh would part from the structure
grid every cell-keyed reader relies on.

**Why the per-cell quads are not lit directly.** The quad-per-cell mesh is the gameplay
resolution; its facets lit by a sun render every grade as a staircase. The grid mesh's own
normals were also inverted until 2026-10-01 (they pointed into the ground, so the terrain was
black under any sun) — fixed, with a regression test.

**Everything drawn from the height's derivatives reads a B-spline-smoothed field.** The height
texture is bilinear, which kinks at every cell edge; a contour, bank edge or lit normal taken
from it zigzags cell by cell across the 45-degree view (2026-10-01: the contours stair-stepped).
The smoothed field is continuous in slope, and it is never used for a gameplay fact.

TODO: hachures (short tapered strokes pointing downhill) are still in the shader but OFF
(`hachure_strength` 0) since 2026-10-01: at game zoom they were one to two pixels wide, so even
antialiased they read as scribble, and the bank tint plus relief lighting answers the same
question without a high-frequency pattern. Alex to decide: reject and delete them, or keep them
as an optional far-zoom / map-view cue.

REJECTED — hachures as continuous stripes, phased by position across the downhill direction
(2026-10-02). Wherever that direction turns — every ramp, pond rim and saddle — the stripes
compress into bands and moire. Stamped strokes carry one direction each, so turning ground only
rotates them.

**Antialiasing.** Every hard edge the shader draws (hachure strokes, grain clumps, the cliff
outline, rock bands, contours) ramps over one screen pixel, measured with `fwidth`; contours also
fade out where levels crowd within a few pixels of each other. Strokes
thinner than a pixel are drawn a pixel wide and fainter rather than breaking into dashes, and
the grain's clumps and the hachures fade out once they shrink to a few pixels, where they would
only crawl and sparkle (2026-10-02). Geometry edges (doodads, buildings, the cell-shaped
coastlines) are outside the shader's reach; that is the renderer's MSAA setting, still off.

Every colour the shader takes comes from the map's `Biome`, in sRGB as the inspector shows it
(the tile colours were read raw until 2026-10-21). TODO: each biome was judged by eye on one map
(skirmish) only; nothing checks that a new palette keeps the rock, ink line and water legible.

TODO: the cues are tuned by eye in the Compatibility renderer under xvfb
(`tools/terrain_visuals/render.sh`), not in Forward+ on real hardware.
