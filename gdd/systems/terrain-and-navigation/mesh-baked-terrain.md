---
title: Mesh baked terrain
type: system-note
---

# Mesh baked terrain

*Design note for [Dissent Horizon](../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

## Terrain can also be BAKED from a surface mesh (`MeshHeightfieldBaker`)


`Map.terrain_source_mesh` is a second author for the same `heights` layer: assign a `Mesh` **on the Map node**, press its `bake_terrain_from_mesh` button, and `MeshHeightfieldBaker` rasterizes it into per-corner heights.

**Both the mesh and the button live on the Map NODE, never on the TerrainData resource, and this is not stylistic — putting them on the resource crashed the Godot editor.** A Resource is drawn as a nested sub-inspector; a resource-valued property *inside* one made the inspector free objects mid-signal (`Object … was freed or unreferenced while a signal is being emitted`, then a dead `EditorInspector::_changed_callback`) and dereference null on the next open. Four crash reports, byte-identical stacks, `EXC_BAD_ACCESS at 0x0` on the main thread inside the run-loop observer — and bisection settled it: clearing the field made the crash stop on both test maps. It reads better this way too: the mesh is an authoring input and the rendered geometry, both scene concerns, while `TerrainData` is the baked gameplay artifact. `TerrainData`'s inspector is now structurally identical to a brush-authored map's, which was never affected. `bake_source_mesh(mesh, transform)` therefore takes the mesh as a PARAMETER. **One-way, on demand, stored in the resource** — the same shape as `tools/spec_import`. Nothing at runtime learns a mesh was involved, load does no work, and the brush can touch up a baked field afterwards.

**Why bake rather than play on the mesh.** The world is one playable surface with structures on a grid, so it must stay a height FUNCTION over XZ — one Y per (x, z). An arbitrary mesh's only extra representational power is exactly what that forbids (overhangs, caves, stacked floors). Measured in this engine at s1's size: a downward raycast against a `ConcavePolygonShape3D` costs **1.43 µs** against **0.445 µs** for the bilinear heightfield read, and `Map.terrain_height_at` runs twice per unit per physics tick (seven times for an aerial one). So the mesh buys no representational power and costs the hottest arithmetic path in the game. Baking keeps the sculpted surface AND the O(1) query.

Three rules carry the mechanic, and each is load-bearing:

- **Vertical triangles are skipped** (`MIN_TRIANGLE_XZ_AREA`). A wall projects to zero XZ area, so it is never the surface anywhere — the cap above it or the ground beside it is. This is what lets a plateau be modelled with *genuinely* vertical sides and still bake into a clean one-cell cliff, which `TerrainGrid`'s `MAX_SLOPE_DIFF` then makes impassable and `HeightmapMeshGenerator` renders as a black cliff face.
- **Highest surface wins.** A modelled plateau is a solid — a cap over a floor — so the playable surface is the top of it. Meshes may be watertight bodies rather than carefully-stitched open sheets, and triangle order does not matter.
- **A cell is surfaced only if ALL FOUR corners were covered.** A cell straddling the surface's edge has no well-defined quad. Uncovered cells are marked in `TerrainData.void_cells`, which puts them out of play — impassable and unrendered — so a disc-shaped island reads as a hole beyond its rim. Uncovered CORNERS still get a height, filled from the nearest covered one, so the picking collider extends flat outward instead of dropping a spurious cliff along the rim.

The bake owns `void_cells` and never touches `tile_types`, so painted materials survive a re-bake.

**No physics.** Sampling is triangle rasterization, not raycasting, so a bake runs identically in the editor, in a headless tool script and in a GUT test — no `World3D`, no collider, no frame to wait for, and deterministic.

**The surface mesh is also what gets DRAWN** (`TerrainSurface`, `scripts/rendering/shaders/terrain_surface.gdshader`). Drawing the heightfield instead renders a curve as a staircase and a modelled cliff as a flight of steps, because the heightfield is the GAMEPLAY resolution — one cell, one quad, one flat normal. The grid keeps deciding passability, placement and navigation; it just stops being the thing on screen.

Which node draws a map follows from how its terrain was authored, and **exactly one of the two may be present** — `Map._regenerate_visual_mesh` refuses to create a `HeightmapMeshGenerator` on a map that has a `TerrainSurface`, because when both exist the grid mesh draws OVER the surface and **silently kills fog of war**: `terrain_material()` prefers `TerrainSurface`, so `Fog` pushes the shroud into the material of the mesh that is now hidden behind an unfogged one. The symptom is "fog stopped appearing on this map" with nothing obviously wrong, and it is easy to cause by accident — the Map's `generate_visual_mesh` inspector button creates the generator and sets its `owner`, so it persists into the saved scene:

| Authored as | Drawn by |
| --- | --- |
| brush-sculpted heights | `HeightmapMeshGenerator` (there is no other surface to draw) |
| a modelled `source_mesh` | `TerrainSurface` |

A source mesh cannot carry in its own vertices the three things the generated mesh bakes in, so each is recovered a different way — and **two of the three deliberately do NOT come from the cell grid, because sampling them per cell is exactly what puts the jaggedness back**:

- **Tile identity and traversability** — per fragment, by world XZ, out of `TerrainData.cell_data_texture()` (one texel per cell, RG8: R = tile index, G = too steep to traverse), nearest-filtered because a tile type is a per-cell fact that must not blend across a boundary. This one IS per cell, because it genuinely is cell data. Void is deliberately NOT in this layer: on a mesh-drawn map the MESH already says "no ground" by not being there, and a per-cell vote paints a cell-resolution halo over geometry the mesh genuinely covers (the baker voids a cell whenever ANY of its four corners is off the mesh — the disc island once grew a sawtooth fringe that way).
- **The play boundary** — tested analytically against the play rectangle (centre + two axes + half-extents, the same frame `PlayArea` carries), so the edge of the world is a straight line instead of a staircase.
- **Cliff shading** — BINARY, from the `cell_data` steep flag, which is literally the test the navmesh runs (corner spread vs `TerrainGrid.MAX_SLOPE_DIFF`). Green means a unit can walk there; black means it cannot. There is deliberately **no gradient**: impassability is a yes/no fact about a cell, and a soft ramp between the two states misreports where the boundary is. An earlier version inferred steepness from the interpolated surface normal — smooth, but both soft-edged and subtly offset, since vertex normals are a central difference spanning neighbouring cells. The cost is that the boundary steps at cell resolution, which is correct: that IS the resolution at which passability is decided.

`Map.terrain_material()` is the seam that keeps this from leaking: `Fog` pushes the shroud into the terrain shader every frame and used to reach it by the hardcoded node name `HeightmapMeshGenerator`, which would silently never find a `TerrainSurface` and leave that map's ground unshrouded. Anything else needing the terrain material must go through it too.

Two reference scenarios are generated by `tools/terrain_meshes/generate_test_meshes.gd` (meshes + baked `TerrainData`) and `scenes/scenarios/test/mesh_terrain_{disc,plateau}.tscn`: a domed disc island on s1's grid, and a square with a vertical-sided cylindrical plateau whose top bakes into an ISLAND no ground unit can path to. `tools/terrain_meshes/verify_scene.gd` boots either headlessly and checks the navmesh builds, forces deploy, and an ordered unit arrives; `preview_scene.gd` renders them with fog off for visual checks. Tests: `tests/test_MeshHeightfieldBaker.gd` (the arithmetic), `tests/test_MeshTerrainScenarios.gd` (the baked product), `tests/test_TerrainSurfaceRendering.gd` (the lookup data + the Fog seam).


---

---

## The bake must SAVE, and must prove it saved

`Map.bake_terrain_from_mesh` rasterizes `terrain_source_mesh` into `TerrainData.heights`.
`bake_source_mesh` mutates the resource **in memory**, and a `TerrainData` bound as an
`ExtResource` is its own file — **saving the scene does not save it.** So the bake looked
perfect in the viewport, was gone on the next load, and left the map drawing one surface while
playing the heights of another. Found 2026-09-11: `skirmish.tscn` had been repointed at
`blue_hole.tres` and rebaked, and the `.tres` on disk still held the previous map's heights
(max 2.0 against the mesh's 3.0).

That is [CLAUDE.md §Regenerating data](../../../CLAUDE.md) with the arrows reversed, and from
the outside it reads as "the terrain_data seems out of sync with terrain_source_mesh".

The bake now ends with `ResourceSaver.save` and then **reloads the file and compares**, the
same shape `make_symmetric_terrain.gd` and `resync_surface_mesh.gd` end with:

```
Map: baked blue_hole.tres -> blue_hole_terrain.tres: 25600/25600 corners covered …
Map: wrote blue_hole_terrain.tres   reload residual 0.000000000   <- must be 0
```

**Saving and looking saved are different, and only reading the file back tells them apart.**

## One terrain_data per map

`TerrainData` is the *baked artifact* of one source mesh, so two maps must never share one:
a bake from either overwrites the other's ground. `skirmish.tscn` and
`scenes/scenarios/test/mesh_terrain_plateau.tscn` both pointed at
`resources/terrain/mesh_plateau_terrain.tres` while having different source meshes, so baking
skirmish silently rewrote the plateau test map. Skirmish now owns
`scenes/map/blue_hole_terrain.tres`.

A map with no `terrain_data` no longer warns and stops: the bake **creates one beside the
source mesh**, named after it (`blue_hole.tres` → `blue_hole_terrain.tres`) and with
`play_size` derived from the mesh extent, so the corner grid spans the mesh instead of being
left at the 50×50 default. The binding is then legible from the filename — which is why
`terrain_data` is no longer shown in the inspector at all (it is stored, or every scene would
lose its terrain; it is simply not an authoring input).

## `generate_visual_mesh` means "redraw", whichever renderer this map has

A map is drawn by exactly one of `HeightmapMeshGenerator` (brush-sculpted grid) or
`TerrainSurface` (authored surface mesh). `Map._rebuild_visual_mesh` used to handle only the
first and return silently otherwise, so on a surface-mesh map the button appeared dead and a
brush stroke never re-pushed the per-cell layers the shader samples. It now dispatches on
whichever node is present, exactly as `Map.terrain_material()` does. It still refuses to
*create* a generator on a surface map: both would draw the same ground, and the grid one
occludes the surface and silently breaks fog.


## A height COMMIT writes both artifacts, or the map silently rots

`Map.sync_source_mesh_heights` pushes `TerrainData.heights` into the surface mesh's vertices
**in memory**. A mesh bound as an `ExtResource` is a file of its own, and saving the SCENE does
not save it — so on a mesh-drawn map every sculpted basin survived the session and vanished on
reload. `terrain_data` kept it; the mesh did not.

From then on the map is split in two: everything that READS heights — units, water, placement,
the navmesh — is correct, while everything you SEE is stale. That is what made a pond render as
a rim with terrain showing through the middle, and it took four rounds to find because the
symptom looks like a rendering bug (see
[water-bodies.md](water-bodies.md) §Water floods against `terrain_data`).

`Map.rebuild_terrain_visuals(true)` is the single commit point every height path funnels
through — stroke end, region paste, undo, mirror, shift — so it now syncs the mesh **and calls
`persist_terrain_artifacts()`, which saves BOTH `terrain_data` and `terrain_source_mesh`.** The
per-step live preview (`apply_terrain_heights_live`) deliberately does not: it runs per mouse
move and this writes a megabyte.

Proved the way §Regenerating data demands — sculpt through the real commit path, reload both
files from disk, and re-bake:

```
mesh file written:         true
terrain_data file written: true
after a reload, mesh vs heights residual: 0.000000000   <- must be 0
```

### Which direction is primary is the trap, and it has bitten twice

`heights` and the surface mesh are the same surface twice and the arrows run BOTH ways. On a
BRUSH-authored map heights are primary and the mesh is written from them
(`tools/terrain/resync_surface_mesh.gd`). On a MODELLED map the mesh is primary and heights are
baked from it (`bake_terrain_from_mesh`). **Running the wrong direction destroys the authoring
silently**: on 2026-09-11 a re-bake was run on a map being sculpted with the brush, and it
overwrote the author's basins with the unchanged mesh. There is no undo for that and the files
were untracked.

Before running either, ask which artifact was edited last. `Map.source_mesh_bake_residual()`
tells you they disagree; it does not tell you which one is right.
