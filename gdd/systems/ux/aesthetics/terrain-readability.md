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
| Where does one level end? | a contour line every terrace step, offset so each step carries exactly one; graded ground leans toward scree colour as it steepens |
| Which way does this slope fall? | **hachures** — short tapered strokes stamped on a jittered grid over walkable sloped ground, each pointing straight downhill at its own centre: the cartographer's slope cue. Whether a stamp inks follows the ground's own steepness there; its direction follows a coarse read of the grade |
| Is this ground tilted at all? | **grain** — a fine stipple of grass clumps in both albedo and the lit normal, so the same bumps catch the sun differently once the ground under them tilts (2026-10-02: the smooth fill gave a slope nothing to show itself with) |
| Is this a pit or a rise? | cavity shading — ground below its local mean (a coarse mip of the height texture) darkens slightly, ground above it brightens |
| Is this the same field everywhere? | two-octave world-space noise and pass-7 ground paint ([visual-facets](../../terrain-and-navigation/visual-facets.md)) |

**Why the per-cell quads are not lit directly.** The quad-per-cell mesh is the gameplay
resolution; its facets lit by a sun render every grade as a staircase. The grid mesh's own
normals were also inverted until 2026-10-01 (they pointed into the ground, so the terrain was
black under any sun) — fixed, with a regression test.

REJECTED — hachures as continuous stripes, phased by position across the downhill direction
(2026-10-02). Wherever that direction turns — every ramp, pond rim and saddle — the stripes
compress into bands and moire. Stamped strokes carry one direction each, so turning ground only
rotates them.

TODO: the cues are tuned by eye in the Compatibility renderer under xvfb
(`tools/terrain_visuals/render.sh`), not in Forward+ on real hardware.
