---
title: Terrain authoring
type: system-note
---

# Terrain authoring

*Design note for [Dissent Horizon](../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

## Terrain visuals + in-editor editing (the `terrain_brush` plugin)


`HeightmapMeshGenerator` (`@tool`, under `NavigationRegion/Body`) generates the visual terrain `ArrayMesh` from the derived `HeightMapShape3D`. It **omits out-of-play cells** (void included), leaving literal geometry holes, and draws a too-steep cell solid black — [map-composition](map-composition.md) §What survives of the tile-type layer.

Terrain is authored in-editor with the **`terrain_brush`** plugin (`addons/terrain_brush`): select a Map, toggle "Terrain Brush" in the spatial-editor toolbar, pick a mode, then left-click-drag over the terrain. Modes:
- **Paint** — sets the hovered cells' ground material (Grass/Dirt/Sand/Rock/Lithium bed) in `terrain_data.tile_types`. A material is art only and never changes passability.
- **Raise / Lower / Smooth / Set** — sculpt `terrain_data.heights` per corner (radial falloff; Set flattens to a target). All height edits are clamped to `[0, 5]` and snapped to `0.5`.

Edits write straight to `terrain_data` (persist with **Save All** / saving the resource) and are one undo action per stroke. The former `HeightPin` / `BlockPin` gizmos, the `heightmap_editor` addon, `Map.generate_editor_pins`, and `Map.blocked_cells` were all removed. `Map._mirror_*` (the mirror authoring tool) operates directly on `terrain_data` (heights + tile types).

## Editor-facing setters must be IDEMPOTENT


A setter that fans out to signals, `notify_property_list_changed()`, resource replacement or
scene edits **must return early when the value has not changed**. `Map.terrain_data`,
`Map.height_map` and `TerrainData.play_size` all do.

This is an editor-stability rule, not tidiness. Expanding a nested resource row makes Godot's
`EditorPropertyResource` **write the resource back** to the property it came from — the same
object, assigned again. An unguarded setter then runs its whole body during that write, and a
`notify_property_list_changed()` inside it tears down and rebuilds the inspector's property
editors *while the inspector is still building the sub-editors for that row*. The symptom is a
pair of `Object ... was freed or unreferenced while a signal is being emitted from it`, then
`Cannot connect to 'property_list_changed': ... 'EditorInspector::_changed_callback'`, and an
editor CRASH the next time the resource is opened.

Two related habits on the same path, both now in `Map`:

- **Mutate a derived resource in place rather than replacing it** when its shape is unchanged
  (`_sync_from_terrain_data` writes `height_map.map_data` instead of building a new
  `HeightMapShape3D`). Replacing frees a resource the inspector may be displaying.
- **Connect a resource's `changed` with `CONNECT_DEFERRED`** when the handler edits the scene.
  Godot propagates `changed` up from sub-resources, so merely expanding a nested row fires it,
  and a synchronous handler does its work inside that emission.

## The brushable surface (`TerrainMeshGrid`)


The terrain brush edits **the surface mesh itself**, not a separate height layer. `Map.create_terrain_mesh` lays down a flat `TerrainMeshGrid` — a subdivided plane with one vertex per grid corner — and brush strokes move those vertices' Y.

Three decisions, each with a reason:

- **One vertex per GAMEPLAY corner.** RA3's World Builder sculpts at its gameplay tile resolution too, and at this resolution baking the drawn surface back into the heightfield is **lossless** (pinned by `test_TerrainMeshGrid.gd`), so the terrain the player sees and the terrain the game simulates cannot disagree.
- **Shared, indexed vertices** — not the four-per-cell layout `HeightmapMeshGenerator` uses. A brush moves ONE vertex and every triangle touching that corner follows; with duplicates the same corner exists four times and would need hand-syncing. Sharing also yields smooth normals free. The per-cell tile identity the duplicated layout carried is not lost — `terrain_surface.gdshader` looks it up per fragment by world XZ, which is why that indirection exists.
- **Full surface rebuild per stroke step, no chunking.** Measured at 7.7 ms for s1's 160×160 grid — 130 fps — so partial-update machinery would be complexity bought for nothing.

**`Map.sync_source_mesh_heights()` is the single write point.** Both height paths call it — `set_terrain_heights` (stroke end, undo) and `apply_terrain_heights_live` (every cell during a drag) — so the mesh and `TerrainData.heights` cannot drift, and a stroke is visible while you make it. A `terrain_source_mesh` that is NOT a grid of the right size (an imported Blender sculpt) is left alone: still drawn, still baked, just not brushable, because "raise everything within radius r" is undefined on arbitrary topology.

**Heights are CONTINUOUS.** The old snap to `HEIGHT_STEP` was a relic of even-length heightmap cells; it is gone from the apply path (the constant is now only the SpinBox's granularity). A feathered brush needs the values in between to make a slope at all.

The brush follows World Builder's Height Brush: **radius**, **feather width**, **target height**. Inside the radius the height is hard-set; across the feather ring it eases out to the existing terrain (smoothstep), and the ring takes the brush's own shape — Euclidean for a circle, Chebyshev for a square. Feather 0 stamps a plateau whose wall exceeds `MAX_SLOPE_DIFF` and is therefore impassable and cliff-shaded; a wide feather makes a walkable mound.

**Ramp mode** drags from one level to the other. Its endpoint heights are SAMPLED from the pre-stroke terrain rather than typed in, which is what makes it mean "connect these two levels" — drag from low ground to a plateau top and the slope follows — and also means re-dragging never accumulates, since every re-apply starts from the same snapshot. The radius is its half-width and the feather softens its long sides; the ends stay hard, because there they already sit at the terrain's own height. Its cross-section is a rectangle, not a capsule: rounded ends would splay sideways where the ramp meets each level instead of finishing square against it. Tests: `tests/test_TerrainRampTool.gd`, which pins the gameplay properties — the ends meet the ground with no step, a long ramp comes out under `MAX_SLOPE_DIFF` (walkable) and a short one over the same rise does not.

**Cliffs in RA3 are PLACED OBJECTS, not terrain.** Cliff models (`YU_SeaCliffWall09`…) are placed with "Align to terrain", rotated and copy-pasted along an edge, and then the terrain is trimmed *to match the prop* with the Height Brush. Ramps likewise: the Ramp tool slopes the terrain, then a ramp object sits on top. So the heightfield only has to be steep enough to be impassable — hard vertical geometry is a prop laid over it. That is why no vertical-skirt geometry or crease-normal work is needed here.
