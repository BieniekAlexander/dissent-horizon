# Terrain Translation (Copy / Paste / Shift)

## TL;DR

**Status: built.** Moving a sculpted region used to mean re-sculpting it by hand; a `TerrainData` grid resize only preserves the top-left corner, so downsizing a map sculpted elsewhere in the grid lost the work. The fix is **one data primitive** — translate a rectangular slice of `heights`/`tile_types` by an offset, with an edge policy for what happens at the seams — exposed through **two entry points**: a `Region` mode in the `terrain_brush` plugin (drag a rectangle, Copy/Move it, click to stamp), and an inspector-triggered whole-map `shift_map` on `Map` following the existing `mirror_map` idiom (for repositioning content before a resize).

Every terrain write is followed by an **entity reconciliation pass** (§4): scene entities standing on changed ground re-seat to the new surface height, and entities the new terrain can no longer support — a unit under a pasted lake, a building with a hillside now running through its footprint — are deleted from the scene tree. Re-seating turned out to be already implemented and free; the cull was the genuinely new work.

### What shipped, by file

| File | What |
| --- | --- |
| `scripts/maps/terrain/terrain_data.gd` | `translate_region` / `shift_all` primitives, `cell_supports_entity` / `cell_is_flat` support predicate |
| `scripts/maps/map.gd` | `apply_terrain_region_paste` / `revert_terrain_region_paste`, `reconcile_entities_with_terrain`, `shift_offset` / `shift_edge_policy` / `shift_map` exports |
| `addons/terrain_brush/terrain_brush_plugin.gd` | `Mode.REGION`: drag-select, Copy/Move, flip + per-layer toggles, terrain-hugging outlines, undo |
| `tests/test_TerrainTranslate.gd` | 21 GUT tests over the primitives and the support predicate |

### Where the implementation corrected the design

Four things this doc originally got wrong, found while building:

1. **`Map.footprint_cells` is unusable at author time.** It filters through `grid_coordinates_in_bounds`, which reads `cell_grid` — and `Map._ready` returns early in the editor, leaving `cell_grid` empty, so it returns *no cells at all*. Footprints are computed in `Map.entity_terrain_cells` instead. `terrain_grid` and `nav_manager` are equally absent while authoring, which is why the support predicate lives on `TerrainData` (§4b).
2. **The flatness cull is per-structure, not universal.** `Structure.allow_uneven` already exists and `Structure.valid_placement` honours it, so the cull must too — otherwise it deletes buildings the game would happily have let the player place.
3. **The clipboard is a source rectangle, not an extracted buffer** (§3a). This makes a Move non-destructive until it actually lands.
4. **The paste preview is an outline, not a translucent ghost** of the region's contents — rendering the latter would mean generating a second terrain mesh on every cursor move.

---

## The problem, concretely

`TerrainData`'s `play_size` setter already refits `heights`/`tile_types` (the grid size is derived from it), but `_remap_layers` always anchors the preserved region at `(0,0)` (top-left) and default-fills the rest. If an author sculpted a fortress in the middle of a 200×200 map and wants a tighter 80×80 map centered on it, shrinking the grid today just crops the top-left 80×80 corner — the fortress is gone unless it happened to already be there. There is no operation that lets the author say "move that content to the corner first," short of repainting every cell and re-sculpting every height by hand with the brush.

Separately, even without resizing, an author who sculpts a canyon in the wrong spot has no way to relocate it — only to erase and redo.

---

## 1. Data model recap

From `scripts/maps/terrain/terrain_data.gd`:

- `heights: PackedFloat32Array` — **per corner**, size `dimensions.x * dimensions.y`, index `z * W + x`. `W = dimensions.x`, `D = dimensions.y`.
- `tile_types: PackedByteArray` — **per cell**, size `grid_width() * grid_depth()` = `(W-1) * (D-1)`, index `z * (W-1) + x`. Empty array means "all Open" (`TerrainTileCatalog.DEFAULT_INDEX`).
- Corners and cells are offset grids: cell `(x, z)` is bounded by corners `(x,z)`, `(x+1,z)`, `(x,z+1)`, `(x+1,z+1)`. **A region of `w × h` cells needs `(w+1) × (h+1)` corners** — one more in each direction. This is the single most important fact for the data-level operation: a "cell rectangle" and its corresponding "corner rectangle" are not the same shape, and every translate has to expand the corner rect by one before reading/writing it.

There's no existing notion of a "selected region" anywhere in the codebase — `terrain_brush` only ever operates on a brush footprint (circle/square) centered on the cursor, applied and released in the same gesture. This feature introduces the first persistent selection/clipboard concept in the terrain-authoring pipeline.

---

## 2. The core data primitive: `translate_region`

Rather than designing "region copy/paste" and "whole-map shift" as two features, they should be **one function with two callers**. Conceptually (illustrative signature, not proposed literal code):

```
translate_region(
  terrain_data: TerrainData,
  source_cells: Rect2i,       # in CELL space (x, z, w, h)
  dest_origin: Vector2i,      # cell-space (x, z) where source_cells.position lands
  layers: {HEIGHTS, TILE_TYPES},   # which layer(s) to touch — see SC2 Editor precedent below
  transform: NONE | FLIP_H | FLIP_V | FLIP_BOTH,
  clear_source: bool,         # Cut vs Copy
  edge_policy: CLIP | WRAP | EXTEND_EDGE  # only meaningful when source_cells == full extent
) -> { new_heights, new_types }
```

### Steps

1. **Read.** Corner rect = `source_cells` grown by 1 in +x/+z (so a `w×h`-cell source reads `(w+1)×(h+1)` corners). Tile-type rect = `source_cells` exactly. Copy both slices out of the *current* `heights`/`tile_types` arrays (never mutate in place while reading — a source/dest overlap, e.g. nudging a region by one cell, would otherwise read already-written data).
2. **Transform.** `FLIP_H`/`FLIP_V` reverse the row or column iteration order when writing the slice back out — this is exactly the reflection math `Map._mirror_heights` / `_mirror_tile_types` already implement (`scripts/maps/map.gd:716-764`), just applied to a sub-buffer instead of the whole grid split at a centerline. `FLIP_BOTH` is both. Plain rotation (90°) is deferred — see Phasing — because it transposes `w` and `h`, which the square/circle brush footprint math never had to deal with.
3. **Place.** Destination corner/cell rects are `dest_origin` + the (possibly transposed) source size. Clip the destination against `[0, dimensions)` — cells that would land out of bounds are dropped, not rejected (same permissiveness as `_stamp_tiles`'s in-bounds check in the brush).
4. **Write into copies.** Same pattern the brush already uses for a stroke (`_stroke_before_heights` / `_stroke_before_types` in `terrain_brush_plugin.gd:66-67`): duplicate the live arrays, mutate the duplicates, and only assign back once the whole op is computed. Never partially mutate `terrain_data.heights` mid-calculation.
5. **Source-side cleanup (Cut only).** When `clear_source` is true, the cells/corners in `source_cells` that were NOT also part of the destination (a Cut-and-move overlapping itself is the corner case) get reset to defaults — height `0.0`, tile type `TerrainTileCatalog.DEFAULT_INDEX` (Open).
6. **Reconcile entities** against the newly-computed arrays — re-seat survivors, cull the unsupportable. Detailed in §4; it runs as part of the same committed operation, not as a separate author-invoked step.
7. **Whole-map shift is source_cells == the full extent, dest_origin == shift_offset.** Here `edge_policy` matters, because every destination cell is in bounds for some interpretation of "wrap": `CLIP` drops what falls off one edge and default-fills what's newly exposed on the other (this is what you want before shrinking the grid); `WRAP` takes the cells that fell off one edge and re-inserts them on the opposite edge (useful for a tileable/looping map); `EXTEND_EDGE` repeats the boundary row/column outward instead of default-filling, avoiding a sudden drop to height 0 at the newly-exposed edge. For a sub-region paste (not the whole map), `edge_policy` doesn't apply — cells outside the pasted footprint that were never part of `dest` are just left untouched.

### Precedent for the "per-layer" toggle

StarCraft II's Galaxy Editor terrain-copy tool (the closest real precedent among tools I know of for this exact feature) lets the author paste height and texture/cliff data independently — you can drop a copied height profile without disturbing the destination's ground texture, or vice versa. WarCraft III's World Editor notably has **no** terrain copy/paste at all — authors work around it with third-party tools or accept re-sculpting — which is itself evidence this is a real, recurring pain point worth solving rather than a nice-to-have. Godot terrain addons in this project's neighborhood (Terrain3D, zylann's `hterrain`) are brush-based like `terrain_brush` and don't ship a built-in region-translate tool either, so there's no in-engine precedent to lean on — the design above is original to this project, built from primitives (`TerrainData`'s array layout, `Map._mirror_*`'s reflection math, the brush's stroke-snapshot pattern) that already exist.

Given that, `layers` should default to `{HEIGHTS, TILE_TYPES}` (both) but be togglable in the UI — an author moving a plateau often wants the shape without dragging the wrong ground texture along with it, or vice versa (copying just a road's tile-type footprint onto different terrain).

---

## 3. UX flow

### 3a. Region copy/paste — a new `terrain_brush` Mode

The plugin had `enum Mode { PAINT, SET }` — Paint writes `tile_types`, Set flattens `heights` under a brush footprint. `REGION` is a third mode that behaves differently from the other two because it isn't a stamp — it's a rectangle drag plus a separate commit step:

1. **Select.** With `REGION` active, left-drag on the terrain defines a rectangle from press-cell to current-cell, drawn as a ground-hugging outline (`_add_rect_outline`, subdivided per cell so it tracks the surface). Releasing commits the selection; no data is written.
2. **Copy / Move.** Toolbar buttons plus `C` / `X`. Both only *arm* a stamp — see the clipboard note below.
3. **Stamp.** While armed, the destination rectangle is outlined in green at the cursor, centred on the hovered cell. Left-click commits it as one undo action (§5). `Flip X` / `Flip Z` mirror the region as it lands. Escape or right-click disarms, keeping the selection so the author can re-arm with different flips.
4. **Layer toggle.** `H` / `T` checkboxes (both on by default) gate the `layers` parameter, per the SC2 precedent above.

**The clipboard is the source RECTANGLE, not an extracted buffer.** The doc originally specified extracted height/tile slices; holding a rectangle turned out to be simpler *and* better behaved, because `translate_region` already reads from the live arrays and writes into copies:

- A **Move is non-destructive until it lands** — `clear_source` happens as part of the same paste, so disarming costs nothing. The originally-specified Cut, which erased immediately and remembered what it erased, would destroy terrain on a keystroke the author might never follow through on.
- A **Copy re-reads live data**, so it can be stamped repeatedly and picks up edits made in between.
- After a Move the selection *follows the content* to its destination, so a second Move chains naturally instead of re-reading the emptied source.

The cost is that cross-map stamping is impossible without a real extracted buffer — that was Phase 5 stretch and is deliberately not built.

`REGION` stays orthogonal to `PAINT`/`SET` the way `Shape`/`Stroke` already are: a new item in the `Mode` dropdown, cycled with `M`. `_on_mode_changed` hides the brush controls (shape/stroke/radius mean nothing here) and shows the region strip. Leaving the mode disarms any armed stamp, since the brush modes offer no way to place or cancel one.

### 3b. Whole-map Shift — an inspector trigger on `Map`

For the "downsize the map" motivating case, a viewport drag-select of the *entire* map is clumsy — the author knows the offset they want numerically ("move everything 40 cells left, 15 up"), not by eyeballing a drag. `Map` already has exactly this shape of feature: `mirror_map` (`map.gd:509`) is a boolean `@export` that, when toggled in the inspector, runs `_run_mirror()` as a side effect — no dedicated UI, just inspector fields plus a button-like boolean. Shift should follow the identical idiom:

```gdscript
@export var shift_offset: Vector2i = Vector2i.ZERO
@export var shift_edge_policy: TerrainData.EdgePolicy = TerrainData.EdgePolicy.CLIP
@export var shift_map: bool:
  set(_v): _run_shift()
```

`_run_shift()` calls `TerrainData.shift_all` and commits through the same `apply_terrain_region_paste` the plugin uses, so the entity reconciliation in §4 applies identically. The motivating recipe:

1. Set `shift_offset` so the region of interest lands at/near `(0,0)` (the corner `_remap_layers` preserves), toggle `shift_map`.
2. Shrink `terrain_data.play_size` to crop around it.

**This path is NOT undoable**, matching `mirror_map`: `Map` has no editor undo history of its own, and a whole-map shift is the same category of deliberate, one-shot operation. It frees the culled entities outright rather than orphaning them. The plugin's `REGION` stamp is the undoable path — that asymmetry is why the cull returns records instead of just freeing nodes itself (§5).

`shift_all` is a separate primitive from `translate_region` rather than a call into it, because the edge policies need a *gather* formulation (each destination samples `cell - offset`) to describe the strip exposed on the trailing edge. `translate_region` scatters a bounded source rect and has nothing to say about cells no source maps onto. Only `CLIP` could have been expressed as `translate_region(full_grid, offset, clear_source = true)`.

---

## 4. Entity reconciliation

Terrain is not authored in isolation — scenario scenes place structures, extraction sites, units and skirmish start points directly on the surface. A paste or shift that changes the ground under them must bring them along, or remove them when the new ground can't hold them. This is part of the operation, not an optional extra: an author who pastes a lake over a barracks should get a lake, not a barracks floating in water.

### 4a. Re-seating is already implemented

`Map._reseat_entities_on_terrain` (`map.gd:577`) already snaps every scene-placed entity's Y to `terrain_height_at(xz)`, and it is already called from `rebuild_terrain_visuals(true)` (`map.gd:568-569`) and `apply_terrain_heights_live()`. Since §5's `apply_terrain_region_paste` ends in `rebuild_terrain_visuals(true)`, **the "entities follow the new height" half of this feature requires no new code** — it just requires not bypassing that path. The one thing to preserve: it re-seats map-wide rather than only inside the pasted rect. That is harmless (re-seating an entity already at its terrain height is a no-op) and is what a whole-map Shift wants anyway.

### 4b. The support test must derive from `TerrainData`, not `TerrainGrid`

`Map._ready` early-returns in the editor (`map.gd:430-433`), so at author time `terrain_grid`, `cell_grid` and `nav_manager` **do not exist**. `TerrainGrid.is_passable` / `is_too_steep` / `is_flat` and `Map.cell_grid` are all unavailable to this feature, and their rules are evaluated directly against `terrain_data`'s arrays by `TerrainData.cell_supports_entity`. It reads `TerrainGrid.MAX_SLOPE_DIFF` (a `const` on the class, readable without an instance) rather than restating `0.5`, so the two can't drift apart.

**This same early-return is a live trap for anything else added here.** `Map.footprint_cells` looks like the obvious way to get a structure's footprint, but it filters every cell through `grid_coordinates_in_bounds`, which reads the empty editor-time `cell_grid` and therefore returns **an empty array at author time** — a cull built on it would silently never fire. `Map.entity_terrain_cells` computes the footprint from `footprint_origin` (which reads `height_map`, and *is* populated in the editor via `_sync_from_terrain_data`) plus the `Structure` component's `dimensions`, with no `cell_grid` involvement.

A cell fails to support anything when any of these holds:

| Condition | Source |
| --- | --- |
| out of bounds | `cell` outside `grid_width()` × `grid_depth()` |
| impassable tile type (water / forest / no-go) | `TerrainData.is_cell_type_passable` |
| no rendered surface — a literal hole in the mesh | `TerrainData.cell_renders_surface` |
| corner-height spread > `TerrainGrid.MAX_SLOPE_DIFF` | computed from `heights`, mirroring `TerrainGrid._mark_steep_cells` (`terrain_grid.gd:389-402`) |
| outside the screen-aligned play bounds | `TerrainData.is_cell_in_play` |

### 4c. Per-kind rules

**Units** (commandables not carrying a `Structure` component) occupy the single cell under `Map.world_to_grid(xz)`. Culled when that cell fails the table above.

**Structures** occupy the footprint from `Map.entity_terrain_cells` (see the `footprint_cells` trap in §4b), with `dims` from the `Structure` component (1×1 fallback, as `add_structure` already does at `map.gd:329-330`). Culled when **any** footprint cell fails the table, **or** — unless the structure sets `Structure.allow_uneven` — when the footprint is no longer flat.

That `allow_uneven` exemption is load-bearing and this doc originally missed it. `TerrainGrid.is_flat` (`terrain_grid.gd:120-128`) requires all four of a cell's corners to be *identical*, so pasting any slope under a barracks invalidates it even though a unit could still walk there — but `Structure.valid_placement` already honours `allow_uneven` when the player places a building, and a cull that ignored it would delete structures the game would happily have allowed. The cull is only permitted to be as strict as placement is.

Usefully, per-cell flatness is sufficient for a multi-cell footprint: adjacent cells share corners, so a contiguous rectangle of individually-flat cells is transitively all one height.

**Extraction sites and Extractors cascade.** `Map.add_structure` hard-fails an `Extractor` with no `ExtractionSite` (`push_error` + bail), and `_mirror_entities` already carries explicit Extractor→site repointing for the same reason (`map.gd:818-828`). So a `Mine` must be culled whenever its bound `Deposit` is culled, regardless of the terrain under the mine itself — otherwise the paste leaves a scene that errors at load rather than one that's merely changed.

**`start_position` markers are never culled.** They're in `_collect_game_entities`'s group list (`map.gd:850`), but they aren't entities — they're skirmish deploy markers matched to player slots by sorted name order (`skirmish.gd:24`). Deleting one silently changes how many slots a map supports, which surfaces much later as a broken skirmish rather than as a visible authoring change. Re-seat them, and `push_warning` if one ends up on unsupportable ground so the author can move it deliberately.

**Only entities over written cells are tested.** `reconcile_entities_with_terrain` takes an optional cell Set; the plugin passes the destination rect ∪ (for a Move) the vacated source rect, and the whole-map Shift passes nothing, which means "test everything". Re-seating stays map-wide as noted in §4a.

### 4d. Report what was deleted

A paste that silently removes six structures is the fastest way to make an authoring tool untrustworthy, so the pass `push_warning`s a summary naming the culled nodes — consistent with how the rest of this layer reports authoring problems (`_run_mirror`'s no-axis warning, `_regenerate_visual_mesh`'s missing-heightmap warning, `GlobalTrigger.arm`'s unresolved-region warning).

## 5. Undo/redo integration

The brush's existing pattern (`_end_stroke`, `terrain_brush_plugin.gd:514-535`) is: snapshot before, mutate, snapshot after, then register **one `UndoRedo` action whose do/undo entries are method calls on the `Map` node** (`set_terrain_heights` / `set_terrain_tile_types`), passing `map` as `custom_context`. The comment there explains why: mixing a `Resource` op (on `terrain_data`) with a `Node` op (on `map`) in the same action produces a "UndoRedo history mismatch" error, so everything is routed as Map methods even though the data lives on the Resource.

Region paste (and whole-map shift) need to touch **both** layers in a single user-visible action — unlike a brush stroke, which only ever edits one layer per action (Paint XOR Set). `Map.set_terrain_heights` and `Map.set_terrain_tile_types` each independently call `rebuild_terrain_visuals`, so registering them as two separate `add_do_method` calls in the same action would work correctness-wise but rebuild the mesh/collider twice. Cleaner: add one combined method, e.g. `Map.apply_terrain_region_paste(new_heights: PackedFloat32Array, new_types: PackedByteArray)`, that assigns both arrays (skipping an array whose "after" equals "before" — a heights-only or tile_types-only paste, per the layer toggle in §3a, should not touch the other array's undo history at all) and calls `rebuild_terrain_visuals(true)` once. Register that one method as the do/undo pair, `custom_context = map`, `UndoRedo.MERGE_DISABLE` — identical shape to the existing calls, just one new Map method instead of reusing two.

Whole-map Shift (§3b) reuses the exact same combined method — it's the same data operation at a different source-rect, so it should not need its own undo plumbing.

### Culled entities go in the same action

Undoing a paste must bring back the units it deleted, so the §4 cull registers into the **same** `UndoRedo` action as the terrain write, using the standard editor idiom per culled node: `add_do_method(parent, "remove_child", node)`, `add_undo_method(parent, "add_child", node)`, and `add_undo_reference(node)` — the last is what keeps the removed node alive instead of letting it be freed. Two properties a naive remove/add pair loses and must be restored explicitly on undo: `owner` (a re-added node with a null owner is not saved with the scene, so the entity would silently vanish on next save) and sibling index via `move_child` (so undo restores tree order rather than appending everything to the end).

Note that `_mirror_entities` calls `node.free()` outright with no undo registration (`map.gd:792`). That precedent should **not** be copied here: mirroring is a one-shot whole-map operation an author invokes deliberately and rarely, while pasting is incremental and frequent, and an unundoable delete on every paste is not survivable.

Mixing method ops on `map` with method ops on each entity's parent is fine — the brush's history-mismatch warning is specifically about mixing a **Resource** op with a **Node** op, and every op here targets a Node in the edited scene, so they share one history. `custom_context` stays `map`.

**Ordering matters on undo.** The re-seat that runs inside `apply_terrain_region_paste` must execute *after* the culled entities are back in the tree, or they'll be restored at their old Y over restored-but-different terrain. Godot's `UndoRedo` executes undo operations in reverse registration order, so registering the terrain op **first** makes it run **last** on undo, after the `add_child` calls — which is the order needed. Worth verifying empirically during implementation rather than trusting the reasoning alone, since getting it backwards produces a subtle wrong-height-on-undo bug rather than an error.

**Ghost preview must stay visual-only.** The brush already separates "live preview during a stroke" (mutates `terrain_data` directly, mesh rebuilds every mouse-move, only committed to undo on release) from "the undo-visible action" (one snapshot pair on release). Region paste's hover-ghost should follow the *second* pattern only — render the ghost as a preview mesh (like `_update_preview`'s ring) without writing into `terrain_data` at all until the click that commits it. Unlike a brush stroke, a paste has no "in-progress" data state to show live (there's nothing to smear) — the ghost is pure visualization, which avoids spamming `terrain_data.changed`/mesh rebuilds on every mouse-move the way a live-mutating approach would.

A Move's source-side clear (step 5 in §2) is **part of the stamp's single undo action**, not a separate one. This follows directly from the clipboard being a source rectangle (§3a): arming a Move writes nothing, so there is no earlier edit to record, and one undo takes the whole move back. The originally-specified Cut — which erased immediately and left the paste as a second, unrelated action — would have needed two undos to restore one move, and would have destroyed terrain on a keystroke the author might never follow through on.

---

## 6. Edge cases

- **Height seams at the paste boundary.** A rectangular paste is a hard-edged write — the corners just inside the pasted rect can differ arbitrarily from the corners just outside it, with no falloff. This is consistent with how `Mode.SET` already behaves today ("a hard set (no falloff)," per the comment at `terrain_brush_plugin.gd:470`), so it's not a new category of roughness the author hasn't already seen — but a rectangle is a much larger and straighter discontinuity than a small stamped circle, so it will read more obviously as a seam. **This is a functional problem, not just cosmetic**: `TerrainGrid`'s `_STEEP` flag trips when adjacent corner heights differ by more than `MAX_SLOPE_DIFF = 0.5` (`terrain_grid.gd:23`), so a paste that creates a seam can silently make a boundary row of cells impassable and exclude them from the navmesh. With §4 in place the seam also has teeth: entities standing on a newly-steep boundary row get culled. That is the cull working as designed, but it means a careless paste can delete a row of units at its own edge. **Accepted, not mitigated** — feather-blending the paste border was considered and declined; it makes the operation non-exact (an author pasting a plateau would get a plateau with mushy edges) and the author can already smooth a seam with a few `Set` or `Smooth` stamps. Paste onto compatible terrain.
- **Terrain can be pasted under a structure without blocking it.** `translate_region` never consults `Map.cell_grid` / `structure_cell_map`, which don't exist at author time anyway (§4b) — the destination is written unconditionally and §4's cull then removes whatever the new ground can't support. There is deliberately **no** placement veto and no red-tint warning on the ghost preview: a paste is an authoring statement about terrain, and the terrain wins. The author sees the consequence immediately (the entity disappears) and can undo. The existing Paint mode has the same shape of behavior today — nothing stops painting a blocked tile under a structure — so this is consistent rather than novel.
- **Entities do not translate with the terrain — they reconcile against it.** Unlike `Map._mirror_entities`, which duplicates and repositions scene entities alongside the heightmap reflection, `translate_region` does not move entities laterally: a structure in the middle of a shifted region stays at its world XZ and is then re-seated or culled per §4. This is deliberate. Lateral entity movement would have to answer questions the terrain operation cannot ("is this extraction site part of the region or scenery next to it?", "what happens to the commands and trigger NodePaths pointing at it?"), whereas reconciliation has exactly one correct answer per entity. An author who wants the buildings moved too can select and drag them — that already works, and it keeps the destructive part of the feature bounded to "things the ground no longer supports."
- **Resize interaction / world-space recentering.** `TerrainData`'s corner-preserving remap is anchored at `(0,0)` in grid-index space, but `Map.grid_to_world`/`terrain_height_at` center the grid on `Map`'s own origin using `(map_width-1)*0.5` (`map.gd:85-97`, `143-160`) — so changing `play_size` also recenters the whole grid in world space, independent of anything this feature does. Shift-then-resize (the recommended recipe in §3b) does not fix this: scene-placed entities' world positions don't move with either the shift or the resize, so after "shift the fortress into the corner, then shrink the play area," the fortress's *terrain* is preserved but the *entities* standing on it end up over different ground. **This interacts badly with §4's cull** and is the one place the two features can combine into data loss: the resize's recentering can drag entities onto unsupportable terrain wholesale. Note the asymmetry — the `play_size` setter is a plain `@export` on the Resource with no cull attached, so a resize alone will *not* delete anything; only a subsequent paste/shift would. The recipe's documentation should say plainly: realign entities after the resize, before the next paste. Making that setter itself entity-aware is out of scope here (it's a `TerrainData` concern, and the Resource has no access to the scene tree).
- **Play-bounds interaction.** `_stamp_tiles` already skips writing tile types to out-of-play cells (`is_cell_in_play` check, `terrain_brush_plugin.gd:458`); a region tile_types paste should do the same, for the same reason (out-of-play cells are masked to holes — writing their type is dead data). Heights are NOT filtered by play-bounds anywhere today (`_stamp_heights` has no such check) because a cell's rendered/navigable status is cell-indexed but corners aren't — an in-play cell right at the play boundary still legitimately uses its out-of-play-adjacent corners for its own shape. Region-paste heights should follow the same unfiltered convention for consistency.
- **Selection/paste crossing the array boundary.** Both `source_cells` and the computed destination rect need clamping to `[0, grid_width) × [0, grid_depth)` (cells) and `[0, map_width) × [0, map_depth)` (corners) independently — a drag-selected rectangle can start or end off-grid if the drag continues past the terrain edge, and a paste offset can be chosen (via the numeric Shift inspector fields) far outside the map. Clip, don't reject — consistent with every other brush operation's bounds handling.
- **Self-overlapping Move.** Nudging a region by less than its own width makes the destination overlap the source, so the clear step must not erase what the move just wrote. Handled by clearing only source cells NOT covered by the destination rect (`_translate_heights` / `_translate_tile_types` both skip cells inside `dest_cells`), rather than clearing the whole source before placing. The heights half needs the corner-space version of that test — both rects grown by one — or the seam column between source and destination gets zeroed. Covered by `test_cut_clears_only_the_part_the_destination_misses`.
- **Catalog compatibility (deferred to Phase 5).** `tile_types` bytes are indices into `terrain_data.catalog`, a `TerrainTileCatalog` resource. Same-map copy/paste is always safe (source and destination share one catalog by construction). A clipboard persisted to disk for reuse across maps/scenarios (Phase 5) is only safe if both maps use the same catalog, or if the paste remaps by tile-type *name* rather than raw byte index — flagged here so Phase 5 doesn't skip it, not something the earlier phases need to solve.
- **Live-preview performance.** Duplicating a `PackedFloat32Array`/`PackedByteArray` on every mouse-move (as the existing `LINE` stroke mode already does, `terrain_brush_plugin.gd:358-389`) is cheap at this project's current map sizes (120×120 default → 14,400 floats) but the ghost-preview step (§5) should still avoid touching `terrain_data` at all during hover, both for undo-cleanliness and so a large clipboard doesn't turn mouse movement into a mesh-rebuild-per-frame cost the way a live-mutating design would.

---

## 7. Status

**Built (phases 1–4):** the `translate_region` / `shift_all` primitives and `cell_supports_entity` on `TerrainData`; `apply_terrain_region_paste` / `revert_terrain_region_paste` / `reconcile_entities_with_terrain` and the `shift_map` inspector trigger on `Map`; `Mode.REGION` in the terrain brush with Copy/Move, flips, per-layer toggles and undo. 21 GUT tests in `tests/test_TerrainTranslate.gd`; full suite 695 passing, with the 7 pre-existing failures (`test_Tool`, `test_SpecRegistry`, `test_ControlBinding`, `test_ScoutVision`, `test_BotTestScenarios`) unchanged from baseline.

**Not verified by tests:** everything above the data layer. The primitives and the support predicate are covered headlessly, and one test asserts the plugin script compiles, but the drag-select interaction, the outline rendering, the undo/redo round trip and the entity cull itself all need a human in the editor — they depend on `EditorInterface`, an edited scene root and viewport input that GUT cannot supply. The undo ordering in §5 in particular (terrain op registered first so it runs last on undo) is reasoned from Godot's reverse-order undo semantics and should be confirmed by actually undoing a stamp that deleted a unit.

**Stretch, not built.** Persist the clipboard as a `.tres` "TerrainStamp" (heights slice + tile_types slice + catalog reference + dimensions) so a sculpted chunk can move between maps — this needs the extracted buffer that §3a deliberately avoided, plus the catalog-compatibility handling from §6. Also 90°/270° rotation, which transposes width/depth unlike the flip transforms.

**Explicitly not planned:** feather-blending at paste seams, ghost-preview warning tint over occupied cells, and lateral entity translation — see §6 for why each was declined.
