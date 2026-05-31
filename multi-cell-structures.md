# Multi-Cell Structure Design

## 1. Current State

The codebase already has partial multi-cell infrastructure, but it is incomplete and has a known visual bug.

**What already works:**

- `TerrainGrid` (`scripts/maps/terrain/terrain_grid.gd`) stores footprints as `_building_footprints: Dictionary # Object -> Array[Vector2i]` and per-cell occupancy as `_building_cells: Dictionary # Vector2i -> Object`. Both already accept arbitrary-length arrays — the data layer requires no changes.
- `NavManager` (`scripts/maps/terrain/nav_manager.gd`) rebuilds the navmesh from `terrain_grid.get_all_passable_cells()` whenever `cells_changed` fires. Multi-cell buildings automatically exclude all their cells from the navmesh — no changes needed.
- `SU.unit_is_close_to_structure` (`scripts/utils/space_utils.gd:61`) already iterates the full registered footprint when checking whether a builder or collector is adjacent — it scales correctly with any footprint shape.
- `StructureSpec` (`scripts/entities/structures/structure_spec.gd`) already carries a `dimensions: Vector2` field, and five structure types are already non-1×1: Outpost (3×3), Lab (2×2), Compound (2×2), Armory (2×2).
- `Map.add_structure` (`scripts/maps/map.gd:124`) and `Commandable.valid_placement` (`scripts/entities/commandable.gd:90`) already iterate a `dims.x × dims.y` rectangle of cells.

**What is broken or missing:**

1. **Visual centering is wrong.** `add_structure` sets `a_structure.global_position = grid_to_world(grid_location)` (line 125 of `map.gd`), where `grid_location` is the *corner* (min-x/min-z) cell of the footprint — not the footprint's visual centre. A 3×3 Outpost ends up anchored to one corner cell rather than its own middle cell. The `# TODO guarantee structure is centered on its cells` comment on line 144 acknowledges this.

2. **Only rectangular footprints are supported.** `dimensions` encodes axis-aligned rectangles. There is no way to describe L-shaped, T-shaped, hollow, or otherwise irregular footprints.

3. **The `placement_checker` callable signature leaks the rectangular assumption.** The signature is `(msg: CommandMessage, dims: Vector2i) -> bool`. Changing from rectangles to arbitrary offsets requires updating this signature and every caller.

4. **`get_grid_coordinates` returns `Vector2` instead of `Vector2i`** (`commandable.gd:64`). Callers cast the result, so it is harmless today, but it is inconsistent and should be fixed in the same pass.

5. **`Build.build_cells`** is populated in `_init` but never read anywhere in the codebase. It is dead code today, likely scaffolding for a future placement-preview system.

---

## 2. Footprint Data: What a Structure Needs to Describe Its Footprint

### Replace `dimensions: Vector2` with `footprint_offsets: Array[Vector2i]`

Each entry is a cell offset from the **origin cell** (defined in §3). The full footprint is `[origin_cell + offset for offset in footprint_offsets]`. A 1×1 structure is `[(0, 0)]`.

The offsets live on `StructureSpec` because that is already the per-type data store:

```gdscript
# scripts/entities/structures/structure_spec.gd  (proposed)
class_name StructureSpec

var placement_checker: Callable
var footprint_offsets: Array[Vector2i]   # replaces `dimensions`

func _init(a_checker: Callable, a_offsets: Array[Vector2i]) -> void:
    placement_checker = a_checker
    footprint_offsets = a_offsets

## Helper: axis-aligned rectangle, origin at top-left corner.
## All offsets are non-negative. Fine for any size, odd or even.
static func rect(w: int, h: int) -> Array[Vector2i]:
    var offsets: Array[Vector2i] = []
    for x in range(w):
        for z in range(h):
            offsets.append(Vector2i(x, z))
    return offsets

static var structure_type_spec_map: Dictionary[int, StructureSpec] = {
    Entity.Type.UNDEFINED:          StructureSpec.new(Commandable.valid_placement, StructureSpec.rect(1, 1)),
    Entity.Type.STRUCTURE_MINE:     StructureSpec.new(Mine.valid_placement,        StructureSpec.rect(1, 1)),
    Entity.Type.STRUCTURE_DWELLING: StructureSpec.new(Commandable.valid_placement, StructureSpec.rect(1, 1)),
    Entity.Type.STRUCTURE_OUTPOST:  StructureSpec.new(Commandable.valid_placement, StructureSpec.rect(3, 3)),
    Entity.Type.STRUCTURE_LAB:      StructureSpec.new(Commandable.valid_placement, StructureSpec.rect(2, 2)),
    Entity.Type.STRUCTURE_COMPOUND: StructureSpec.new(Commandable.valid_placement, StructureSpec.rect(2, 2)),
    Entity.Type.STRUCTURE_ARMORY:   StructureSpec.new(Commandable.valid_placement, StructureSpec.rect(2, 2)),
}
```

An irregular footprint is defined by listing offsets explicitly. For example, a 3×3 ring (hollow centre) for a future structure type:

```gdscript
# fmt: one offset per entry, (x, z) in grid space
StructureSpec.new(Commandable.valid_placement, [
    Vector2i(0,0), Vector2i(1,0), Vector2i(2,0),
    Vector2i(0,1),                Vector2i(2,1),
    Vector2i(0,2), Vector2i(1,2), Vector2i(2,2),
])
```

No changes to the scene files are needed: footprint shape is data, not geometry.

### Do not put footprint data on the scene or on the Commandable instance

`StructureSpec.structure_type_spec_map` is the authoritative per-type lookup. Duplicating footprint data as an `@export` array on the scene would create a second source of truth that could drift. If you later want designer-friendly editing in the Godot inspector, introduce a `FootprintResource extends Resource` and store it in `StructureSpec`, not on the entity scene directly.

---

## 3. Origin Cell Convention

The **origin cell** is the grid cell returned by `world_to_grid(clicked_world_xz)`. All footprint offsets are added to it to produce the full set of occupied cells. With `rect(w, h)`, the origin cell is the top-left (min-x, min-z) corner of the footprint.

This is the convention the current code already uses: `valid_placement` and `add_structure` both start from `world_to_grid(clicked_pos)` and expand by `dims.x × dims.y`.

**Why not use a centred origin (click = centre of footprint)?**  
It is more intuitive for the player, but it complicates even-dimension structures (a 2×2 has no centre cell) and requires changing the coordinate from which all existing validation and registration logic expands. Keeping top-left-corner origin preserves the current code shape; the visual centering problem is fixed separately (§4) without touching the convention.

The origin cell is passed as `grid_location: Vector2i` to `Map.add_structure` — that name should be updated to `origin_cell` throughout for clarity.

---

## 4. How Visual Centering Changes (`Map.add_structure`)

### The fix: set `global_position` to the centroid of the footprint

Replace the single `grid_to_world(grid_location)` call with the average of `grid_to_world` over every cell in the footprint. For odd-dimension rectangles this is exact (the centre cell's world position equals the centroid). For even-dimension rectangles it places the mesh at the midpoint between cells, which is the correct visual result regardless of terrain height variation:

```gdscript
# map.gd — add_structure (proposed)
func add_structure(a_structure: Commandable, origin_cell: Vector2i, rotation: int, _rebake: bool = true) -> void:
    var spec: StructureSpec = StructureSpec.structure_type_spec_map.get(a_structure.type)
    var offsets: Array[Vector2i] = spec.footprint_offsets if spec != null \
        else StructureSpec.rect(a_structure.width, a_structure.length)

    var footprint: Array[Vector2i] = []
    var centroid := Vector3.ZERO
    for offset in offsets:
        var cell := origin_cell + offset
        if not grid_coordinates_in_bounds(cell):
            continue
        footprint.append(cell)
        cell_grid[cell.x][cell.y] = a_structure
        centroid += grid_to_world(cell)

    if not footprint.is_empty():
        centroid /= footprint.size()
    a_structure.global_position = centroid   # centred on actual footprint, not on origin corner

    structure_cell_map[a_structure] = footprint
    terrain_grid.place_building(footprint, a_structure)
    a_structure.map = self
```

This also removes the now-unnecessary `# TODO guarantee structure is centered` comment.

The `entity.gd:_auto_initialize` code at line 151 also calls `add_structure`. It recovers the origin cell from the scene-placed structure's visual position: `found_map.world_to_grid(VU.inXZ(pre_init_pos))`. After this change the origin cell passed to `add_structure` is the top-left corner of the footprint. For a scene-placed 3×3 Outpost whose visual centre is at `pre_init_pos`, `world_to_grid(visual_centre)` floors to the centre cell, not the corner. **This is a misalignment for any structure larger than 1×1.** See §7 for the fix.

---

## 5. How Placement Validation Changes

### `Commandable.get_grid_coordinates` → `footprint_cells`

Replace the current helper, which returns `Array[Vector2]` (floats — a latent type bug), with one that accepts the offset array directly:

```gdscript
# commandable.gd (proposed)
static func footprint_cells(origin: Vector2i, offsets: Array[Vector2i]) -> Array[Vector2i]:
    var result: Array[Vector2i] = []
    for offset in offsets:
        result.append(origin + offset)
    return result
```

### `Commandable.valid_placement`

Update the second parameter from `a_dimensions: Vector2i` to `a_offsets: Array[Vector2i]`:

```gdscript
static func valid_placement(a_command_message: CommandMessage, a_offsets: Array[Vector2i]) -> bool:
    var placement_map: Map = a_command_message.map
    if placement_map == null:
        return false
    var origin: Vector2i = placement_map.world_to_grid(a_command_message.xz_position)
    for cell in footprint_cells(origin, a_offsets):
        if not placement_map.grid_coordinates_in_bounds(cell):
            return false
        if placement_map.cell_grid[cell.x][cell.y] != null:
            return false
    return true
```

The callers in `build.gd:26` and `mine.gd:5` pass `StructureSpec.dimensions` today; they must be updated to pass `StructureSpec.footprint_offsets`.

### `Commandable.get_arrangement_cells`

This is called by `Build._init` to populate `build_cells`. Update the third parameter from `a_dimensions: Vector2i` to `a_offsets: Array[Vector2i]`:

```gdscript
static func get_arrangement_cells(a_map: Map, a_point: Vector2, a_offsets: Array[Vector2i]) -> Set:
    var origin: Vector2i = a_map.world_to_grid(a_point)
    var cells := footprint_cells(origin, a_offsets)
    if cells.any(func(c: Vector2i): return not a_map.grid_coordinates_in_bounds(c)):
        return Set.Empty
    return Set.new(cells.map(func(c: Vector2i): return a_map.cell_grid[c.x][c.y]))
```

### `Mine.valid_placement`

Update the stub signature to match:

```gdscript
# mine.gd
static func valid_placement(a_command_message: CommandMessage, a_offsets: Array[Vector2i]) -> bool:
    push_error("TODO")
    return true
```

---

## 6. How the Build Command Changes

### `Build.meets_precondition` (build.gd:26–28)

Pass `footprint_offsets` instead of `dimensions`:

```gdscript
if not StructureSpec.structure_type_spec_map[a_message.tool.type].placement_checker.call(
    a_message,
    StructureSpec.structure_type_spec_map[a_message.tool.type].footprint_offsets
):
    return PreconditionFailureCause.INVALID_PLACEMENT
```

### `Build._build_reach` (build.gd:38–42)

The current formula `max(dims.x, dims.y) * 0.5 + 1.0` approximates "half the longest side plus one buffer cell". With arbitrary offsets the equivalent is the maximum Chebyshev distance from the origin offset `(0, 0)` to any offset in the footprint, plus one buffer cell:

```gdscript
func _build_reach() -> float:
    if message.tool == null:
        return 1.5
    var offsets: Array[Vector2i] = StructureSpec.structure_type_spec_map[message.tool.type].footprint_offsets
    var max_dist := 0
    for offset in offsets:
        max_dist = maxi(max_dist, SU.linf_distance(Vector2i.ZERO, offset))
    return float(max_dist) + 1.0
```

For a 3×3 rect with offsets (0,0)–(2,2), the farthest offset from (0,0) is (2,2) at Chebyshev distance 2. Reach = 3.0 — one cell larger than before (was 2.5), which is fine.

### `Build._init` — `build_cells` (build.gd:71–77)

Update to pass `footprint_offsets`:

```gdscript
func _init(a_message: CommandMessage) -> void:
    super(a_message)
    build_cells = Commandable.get_arrangement_cells(
        a_message.map,
        VU.inXZ(a_message.position),
        StructureSpec.structure_type_spec_map[a_message.tool.type].footprint_offsets
    )
```

Note: `build_cells` is currently never read. It appears to be scaffolding for a future placement-preview highlight system. The update here future-proofs it, but it requires no functional logic changes until the preview system is built.

---

## 7. Scene-Placed Structures (`Entity._auto_initialize`)

`Entity._auto_initialize` (entity.gd:151–157) recovers the origin cell from `world_to_grid(pre_init_pos)` where `pre_init_pos` is the structure's `global_position` as set in the Godot editor. After §4's centroid change, `add_structure` will position the structure at the footprint centroid — but only for structures placed *programmatically*. Editor-placed structures self-register via `_auto_initialize`, and there the position is set by the designer, not by `add_structure`.

The problem: `world_to_grid(visual_centre)` floors to the nearest cell. For a 3×3 structure placed visually at cell centre (6, 6), `world_to_grid` returns (6, 6) correctly — and since the footprint offsets for a 3×3 rect are (0,0)–(2,2), the registered footprint becomes (6,6)–(8,8), shifted one cell down/right from where the designer intended it to sit.

**The fix**: `_auto_initialize` must subtract the footprint's "centroid offset" from the recovered origin to find the true top-left corner:

```gdscript
# entity.gd — _auto_initialize (proposed)
if is_in_group("structure") and not found_map.structure_cell_map.has(self):
    var spec := StructureSpec.structure_type_spec_map.get(type)
    var visual_cell := found_map.world_to_grid(VU.inXZ(pre_init_pos))
    var origin_cell := visual_cell
    if spec != null:
        # Shift back from visual centre to top-left origin corner.
        # For rect(w, h) the centroid offset is floor((w-1)/2, (h-1)/2).
        var offsets := spec.footprint_offsets
        var sum := Vector2i.ZERO
        for o in offsets:
            sum += o
        var centroid_offset := Vector2i(sum.x / offsets.size(), sum.y / offsets.size())
        origin_cell = visual_cell - centroid_offset
    found_map.add_structure(self, origin_cell, 0, false)
```

This means a scene-placed 3×3 Outpost whose mesh is centred at the editor position will be registered at the correct top-left origin cell, and `add_structure` will then reposition its `global_position` to the computed centroid. The position will shift slightly from the designer's raw editor position to the grid-snapped centroid — this is the correct behaviour.

---

## 8. Grid Registration and Unregistration

`TerrainGrid.place_building` and `remove_building` already accept arbitrary `Array[Vector2i]` footprints (terrain_grid.gd:99–118). No changes are needed there.

`Map.remove_structure` (map.gd:148–153) already drives teardown by reading the registered footprint from `terrain_grid.get_building_cells(a_structure)`:

```gdscript
func remove_structure(a_structure: Commandable, _rebake: bool = true) -> void:
    var cells: Array = terrain_grid.get_building_cells(a_structure)
    for cell: Vector2i in cells:
        cell_grid[cell.x][cell.y] = null
    terrain_grid.remove_building(a_structure)
    structure_cell_map.erase(a_structure)
```

This code is shape-agnostic and requires no changes.

`Commandable._on_death` (commandable.gd:313) calls `map.remove_structure(self)` which chains to the above — also unchanged.

---

## 9. Navmesh Exclusion

No changes needed. `NavManager._build_mesh` (nav_manager.gd:61) iterates `terrain_grid.get_all_passable_cells()`, which returns every in-bounds cell that `is_building_at` returns false for. Placing a multi-cell structure fills multiple entries in `_building_cells`, and the navmesh rebuild (triggered by `cells_changed`) automatically excludes every one of them.

---

## 10. Other Systems That Touch "Which Cell Is This Structure On"

| System | Current behaviour | Change needed? |
|---|---|---|
| `TerrainGrid._building_cells / _building_footprints` | Arbitrary `Array[Vector2i]` — already generic | **No** |
| `NavManager` | Responds to `cells_changed`, queries passable cells | **No** |
| `SU.unit_is_close_to_structure` | Iterates full `structure_cell_map[structure]` footprint | **No** |
| `Commandable.map_cells` (property, line 52) | Reads `structure_cell_map` — footprint-agnostic | **No** |
| `Map.remove_structure` | Reads footprint from `terrain_grid` — shape-agnostic | **No** |
| `Map.cell_grid` | `O(1)` cell→structure lookup, populated per-cell | **No** — `add_structure` loop already handles it |
| `Build.can_act` / `should_move` | Uses `message.world_position` (click) + reach | Reach formula needs update (§6) |
| `Build.meets_precondition` | Passes `dimensions` to `placement_checker` | Passes `footprint_offsets` instead (§5) |
| `Commandable.valid_placement` | Iterates rectangular dim loop | Iterates `footprint_offsets` array (§5) |
| `Map.add_structure` | Uses `dims.x × dims.y` loop + wrong centering | Use offset loop + centroid positioning (§4) |
| `Entity._auto_initialize` | `world_to_grid(visual_pos)` → origin | Subtract centroid offset (§7) |
| `Mine.valid_placement` stub | `(msg, dims: Vector2i)` | `(msg, offsets: Array[Vector2i])` (§5) |
| `Launch.meets_precondition` (launch.gd:11–16) | Dead code (line 5 returns early before this block); references `cube_grid_arrangement` which does not exist in `StructureSpec` | Update or delete the dead block when `Launch` is revived |
| `StructureSpec` | `dimensions: Vector2` | Replace with `footprint_offsets: Array[Vector2i]` (§2) |

---

## 11. Summary of Changes

Five files require edits. Three files require no changes at all.

**`scripts/entities/structures/structure_spec.gd`** — replace `dimensions: Vector2` with `footprint_offsets: Array[Vector2i]`; update `_init`; add `StructureSpec.rect(w, h)` static helper; update all entries in `structure_type_spec_map`.

**`scripts/maps/map.gd`** — fix `add_structure`: compute footprint from `spec.footprint_offsets` + in-bounds guard; set `global_position` to the footprint centroid rather than `grid_to_world(corner)`.

**`scripts/entities/commandable.gd`** — rename/replace `get_grid_coordinates(center, dims)` with `footprint_cells(origin, offsets)`; update `valid_placement` second param from `dims: Vector2i` to `offsets: Array[Vector2i]`; update `get_arrangement_cells` third param similarly.

**`scripts/interface/commands/build.gd`** — update `meets_precondition` to pass `footprint_offsets`; rewrite `_build_reach` to use max Chebyshev extent of offsets; update `_init` to pass `footprint_offsets`.

**`scripts/entities/entity.gd`** — fix `_auto_initialize` to subtract the footprint centroid offset before calling `add_structure`, so the editor-placed visual position maps to the correct top-left origin cell.

**No changes required in:** `terrain_grid.gd`, `nav_manager.gd`, `space_utils.gd`.

---

## 12. Open Questions

**Rotation.** Nothing in this design supports rotating a footprint. The `rotation: int` parameter already exists in `add_structure` (always passed as `0`) and as a column in `configs/scenarios/*/init.json`. If footprint rotation is needed, the clean approach is a utility `StructureSpec.rotate_offsets(offsets, turns: int) -> Array[Vector2i]` that applies 90°-CW rotation (`(x, z) → (z, -x)` then normalise to non-negative coords) before the footprint is registered.

**Footprint for `Entity.width` / `Entity.length` fallback.** `entity.gd` declares `var width: int = 1` and `var length: int = 1`, used only as the fallback in `add_structure` when `spec == null` (e.g., Turret at `Entity.Type.STRUCTURE_TURRET` which has no entry in `structure_type_spec_map`). Either add Turret to the spec map or give `entity.gd` a `footprint_offsets: Array[Vector2i]` fallback field. The latter avoids the separate `width`/`length` fields.

**Placement-preview highlight.** `Build.build_cells: Set` is dead scaffolding. When a placement-preview system is implemented, `build_cells` should hold the `footprint_cells(origin, offsets)` array (not entity references from `cell_grid`) and be recomputed each frame as the cursor moves — not once in `_init`.
