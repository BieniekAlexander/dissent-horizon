# dissent-horizon — terrain representation design note

Context note for implementation (e.g. reference from `CLAUDE.md` or keep in `docs/`).
Captures terrain decisions from a planning conversation.

## Engine context

dissent-horizon is a **3D game and is staying 3D.** A move to a 2D / isometric engine was considered and rejected, for reasons worth keeping on record:

- A 2D **art style**, if wanted, can be done with sprites/billboards rendered in the 3D engine; a fixed camera angle makes that clean. It does not require a 2D engine.
- The game is **height-aware** (plateaus, elevation, arcing projectiles, height-based line of sight), so 3D provides that physics natively. A 2D engine would force re-adding a Z axis — the RA2-style 2.5D bookkeeping — which is fiddly and bug-prone.
- **Pathfinding cost is the same either way.** Units are surface-constrained, so navigation runs on a 2D grid / navmesh laid over the terrain regardless of engine dimensionality. Height folds in as a per-cell attribute, not an extra search dimension.
- Full 2D would only be justified to target hardware that can't do accelerated 3D at all, which is not a goal here.

## Goal

Support **plateaus with flat tops and vertical sides**, in the visual style of Red Alert 2 / Red Alert 3 — not the slope-only terrain of Age of Empires 2.

## Core constraint

A single-value heightmap is a function `y = f(x, z)` — exactly one height per horizontal cell. Therefore it **cannot** represent:

- truly vertical walls (infinite slope)
- overhangs or caves (surface folding back over itself)

Approximating a wall with a steep one-cell gradient is possible but produces texture stretching/smearing on the near-vertical face and never reaches a true 90°. Treated as the rejected "naive" option.

## Chosen approach: heightmap + generated cliff skirt (hybrid)

Keep a heightmap for the bulk of the terrain, but generate dedicated vertical geometry at elevation discontinuities rather than baking the wall into the height function.

### Build steps

1. Store elevation as **discrete levels** wherever plateaus are wanted (snap heights to steps).
2. At mesh-build time, walk each cell and compare it to its neighbors:
   - neighbor on the same level → tessellate the top surface normally
   - neighbor a full cliff-step lower → **emit a vertical quad (2 tris)** dropping from the upper cell edge to the lower neighbor's height
3. Give cliff-face quads their **own UV set** so they don't inherit the stretched top-surface mapping.

### Corners

- Use the **8-neighborhood** (not just 4) when detecting cliff edges, or diagonal cliff corners will have gaps.
- Outer corners: two perpendicular cliff quads sharing a vertical edge. Inner corners (notches): concave meeting of two faces. Same neighbor-check logic handles both.

### Gameplay metadata (free from the same pass)

- Any cell whose neighbor differs by a cliff-step is a **plateau edge** → natural **pathfinding blocker** and **non-buildable** zone.
- Do edge detection and geometry generation in the same pass.

## Optional extension: continuous terrain + selective skirting

If both gentle rolling hills *and* sharp plateaus are wanted (RA3-style), keep continuous heights for general terrain and only **snap-and-skirt** where the gradient between neighbors exceeds a cliff threshold. More code, but gets both.

## Out of scope

Overhangs / caves. These genuinely exceed single-value heightmaps and would require **layered heightmaps** (a small stack of surfaces per column) or **voxels**. RA-style plateaus don't need them.

## References

Visual target is RA2/RA3-style plateaus (flat tops, sharp vertical sides). Architecturally, RA3 is the only close precedent because it is 3D; the others are 2D engines, so only their look or design lessons transfer, not their implementation.

| Reference | Design lesson |
|-----------|---------------|
| Age of Empires 2 | Anti-pattern: no true vertical terrain — elevation changes are always sloped and "cliffs" are decorative objects. We want real vertical faces instead. |
| Red Alert 3 | Architectural model: 3D heightfield with discrete elevation levels and distinct vertical faces — closest to the heightmap + skirt approach here. |
