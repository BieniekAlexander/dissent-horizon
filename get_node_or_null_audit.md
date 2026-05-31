# `get_node_or_null` Audit

25 occurrences across 10 files. Each entry shows the call, what happens if it returns null, and a verdict.

**Verdicts:**
- ✅ **Legitimate optional** — null is a valid runtime state; `get_node_or_null` is correct here
- ⚠️ **Borderline** — null is handled gracefully but the path being set and missing is probably a bug
- 🚨 **Likely should be required** — null silently disables behaviour that should always be present

---

## `scripts/entities/entity.gd`

### Line 44 — `movement`
```gdscript
@onready var movement: Movement = get_node_or_null("Movement") as Movement
```
**Used for:** All pathfinding (velocity, nav agent, terrain snapping). Every caller gates on `movement != null`.  
**If null:** Entity is treated as stationary — correct for structures, items, projectiles.  
**Verdict:** ✅ Legitimate optional. Explicitly documented: "Null for entities that don't (structures, items)."

---

### Line 67 — `vision_range_shape`
```gdscript
@onready var vision_range_shape: CollisionShape3D = get_node_or_null("VisionRange")
```
**Used for:** `get_aggro_near_position()` and `_get_vision_range_attack()`, both return early if null.  
**If null:** Entity never initiates aggro from VisionRange — fine for workers, projectiles.  
**Verdict:** ✅ Legitimate optional.

---

### Line 97 — `collider`
```gdscript
@onready var collider: CollisionShape3D = get_node_or_null("Body")
```
**Used for:** Declared but never directly read anywhere in the codebase. Note that `collision_radius` uses `$Body.shape` directly (not this field), so a missing `Body` node would crash `collision_radius` regardless.  
**If null:** `collider` silently holds null with no caller consequences — but only because no caller reads it. `$Body` is implicitly required by `collision_radius` and by `CharacterBody3D` physics, so the node is always present in practice.  
**Verdict:** 🚨 Likely should be required. `Body` is a prerequisite for the entity to function at all. Either assert it exists or use `$Body` directly and drop this field.

---

### Line 98 — `aggro_range_shape`
```gdscript
@onready var aggro_range_shape: CollisionShape3D = get_node_or_null("AggroRange")
```
**Used for:** `get_aggro_near_position()`, which returns null immediately if this is null.  
**If null:** Entity never auto-aggros. Correct for technicians, structures without weapons.  
**Verdict:** ✅ Legitimate optional.

---

### Line 104 — `weapon_inventory`
```gdscript
@onready var weapon_inventory: Inventory = get_node_or_null("Inventory") as Inventory
```
**Used for:** All weapon queries (`weapon_for_target`, `any_weapon_can_target`).  
**If null:** Entity is unarmed. Correct for technicians, non-combat structures.  
**Verdict:** ✅ Legitimate optional. Documented: "Null for entities that carry no weapons."

---

### Line 179 — `own` in `_apply_team_tint()`
```gdscript
var own := get_node_or_null("Ownership") as Ownership
var id: int = own.commander_id if own != null else 0
```
**Used for:** Reading `commander_id` to pick team colour. Falls back to id 0 (white) if null.  
**If null:** Entity rendered in neutral colour — intentional for out-of-tree build previews whose `@onready` nodes never resolve.  
**Verdict:** ✅ Legitimate optional. Comment explains the out-of-tree preview case explicitly.

---

### Line 181 — `sprite` in `_apply_team_tint()`
```gdscript
var sprite: Node = get_node_or_null("Sprite")
if sprite != null and "modulate" in sprite:
    sprite.modulate = TEAM_COLOR_MAP.get(id, Color.WHITE)
```
**Used for:** Applying team tint. Null-checked before use.  
**If null:** No tint applied — silent, correct for entities without a sprite (e.g., projectiles, items).  
**Verdict:** ✅ Legitimate optional. Same out-of-tree preview rationale, plus genuinely sprite-less entity types exist.

---

### Line 191 — `own` in `configure_preview_ownership()`
```gdscript
var own := get_node_or_null("Ownership") as Ownership
if own != null:
    own.commander = a_commander
```
**Used for:** Assigning commander to a build preview instance before it's added to the tree.  
**If null:** Commander not assigned — would be a silent failure if a preview somehow lacks Ownership.  
**Verdict:** ✅ Legitimate optional. Called on out-of-tree instances; `@onready` can't be used here. But all entity scenes should have Ownership, so a null here would in practice be a scene-setup bug. Could add a `push_warning` on null.

---

## `scripts/entities/commandable.gd`

### Line 21 — `production`
```gdscript
@onready var production: Production = get_node_or_null("Production") as Production
```
**Used for:** Training units, rally points, train-bar rendering. All callers gate on `production != null`.  
**If null:** Entity cannot train units — correct for units and non-training structures.  
**Verdict:** ✅ Legitimate optional.

---

### Line 22 — `resource_provider`
```gdscript
@onready var resource_provider: ResourceProvider = get_node_or_null("ResourceProvider") as ResourceProvider
```
**Used for:** Applying/removing population contributions when commander changes. Gated on `resource_provider != null`.  
**If null:** No population contribution — correct for most entity types.  
**Verdict:** ✅ Legitimate optional.

---

### Line 23 — `ore_extractor`
```gdscript
@onready var ore_extractor: OreExtractor = get_node_or_null("OreExtractor") as OreExtractor
```
**Used for:** `ore_extractor.tick()` in `_update_state`. Gated on `ore_extractor != null`.  
**If null:** Entity doesn't mine — correct for everything except Mine.  
**Verdict:** ✅ Legitimate optional.

---

### Line 24 — `dominion_generator`
```gdscript
@onready var dominion_generator: DominionGenerator = get_node_or_null("DominionGenerator") as DominionGenerator
```
**Used for:** `dominion_generator.tick()` in `_update_state`. Gated on `dominion_generator != null`.  
**If null:** Entity doesn't generate dominion — correct for everything except Outpost.  
**Verdict:** ✅ Legitimate optional.

---

### Line 41 — `_debug_label`
```gdscript
@onready var _debug_label: Label3D = get_node_or_null("DebugLabel") as Label3D
```
**Used for:** Showing active command name when `debug_info` action is held. Gated on `_debug_label != null`.  
**If null:** No debug overlay. Expected for all production entity scenes.  
**Verdict:** ✅ Legitimate optional.

---

### Line 197 — `sprite` in `_process()`
```gdscript
var sprite: Sprite3D = get_node_or_null("Sprite") as Sprite3D
```
**Used for:** Flipping sprite on movement direction; modulating alpha based on `build_progress`. Gated on `sprite != null` at each use-site.  
**If null:** No sprite animation — silent. Called every frame on all Commandables.  
**Verdict:** ✅ Legitimate optional. Commandable is the base class for both units (have sprites) and some structures (may not). Fetching it per-frame instead of caching as `@onready` is worth noting as a minor performance concern, but the null-handling logic is correct.

---

## `scripts/entities/components/movement.gd`

### Line 36 — `_nav_agent`
```gdscript
if not nav_agent_path.is_empty():
    _nav_agent = get_node_or_null(nav_agent_path) as NavigationAgent3D
```
**Used for:** All navigation: target position, velocity, path queries. Every method gates on `_nav_agent != null`.  
**If null:** Movement component does nothing — entity neither navigates nor moves.  
**Verdict:** 🚨 Likely should be required. A `Movement` component whose nav agent is missing silently makes the entity unresponsive to all move commands, with no error. If `nav_agent_path` is set but the node doesn't exist, it's a misconfigured scene. Should assert: `assert(_nav_agent != null, "Movement: nav_agent_path '%s' not found" % nav_agent_path)` when the path is non-empty.

---

## `scripts/entities/components/production.gd`

### Line 46 — `_train_bar`
```gdscript
if not train_bar_path.is_empty():
    _train_bar = get_node_or_null(train_bar_path) as Node3D
```
**Used for:** Visual training progress bar. `update_bar()` returns early if `_train_bar == null`.  
**If null:** Training still works; only the visual bar is absent.  
**Verdict:** ⚠️ Borderline. An empty path deliberately suppresses the bar — fine. But if the path is non-empty and the node is missing, training silently proceeds with no visual and no error. Consider asserting when path is set.

---

### Line 82 — `fill` in `update_bar()`
```gdscript
var fill: Node3D = _train_bar.get_node_or_null("TrainBarFill") as Node3D
if fill == null: return
```
**Used for:** Scaling and positioning the fill portion of the train bar.  
**If null:** Bar is visible but fill doesn't animate — bar appears permanently full/empty with no error.  
**Verdict:** 🚨 Likely should be required. This is called on `_train_bar`, which already exists. A TrainBar without a TrainBarFill child is a broken scene. Should use `get_node("TrainBarFill")` or assert, not silently no-op.

---

## `scripts/entities/components/selectable.gd`

### Line 41 — `node` (indicator)
```gdscript
var node: Node = get_node_or_null(indicator_path)
if node is Node3D:
    set_indicator(node)
elif node != null:
    push_warning("Selectable.indicator_path points at non-Node3D: %s" % node)
```
**Used for:** Visual selection ring/indicator shown when entity is selected.  
**If null:** Entity is selectable but has no visual indicator — silent, handled.  
**Verdict:** ✅ Legitimate optional. The warning on wrong-type is good practice.

---

## `scripts/entities/tools/projectile.gd`

### Line 17 — `hit_shape`
```gdscript
@onready var hit_shape: CollisionShape3D = get_node_or_null("HitShape")
```
**Used for:** `_apply_hit()` runs a shape overlap query using this shape. Returns immediately if null: `if hit_shape == null or not is_instance_valid(target): return`.  
**If null:** Projectile travels, lands, and does **zero damage** with no error or warning.  
**Verdict:** 🚨 Likely should be required. A projectile that deals no damage is a silent scene misconfiguration, not a legitimate optional. Should assert or use `get_node("HitShape")`.

---

## `scripts/entities/tools/weapon.gd`

### Line 38 — `attack_range_shape`
```gdscript
@onready var attack_range_shape: CollisionShape3D = get_node_or_null("AttackRange")
```
**Used for:** `SU.is_in_attack_range()` — if null, weapon uses melee XZ distance instead of shape overlap.  
**If null:** Weapon operates as melee (centre-to-centre distance ≤ `melee_range`).  
**Verdict:** ✅ Legitimate optional. The docstring explicitly documents the null = melee contract. This is a designed two-mode weapon system.

---

## `scripts/interface/command_context_parser.gd`

### Line 126 — `production` in `train_tools_for()`
```gdscript
var production := a_entity.get_node_or_null("Production") as Production
if production == null:
    return result
```
**Used for:** Querying which unit types the entity can train, to build the HUD train menu.  
**If null:** Returns empty array — correct for units and non-training structures.  
**Verdict:** ✅ Legitimate optional. This is a discovery/query call on an arbitrary entity; null is the expected result for most entity types.

---

## `scripts/interface/commands/capture.gd`

### Line 34 — `provider` in `fulfill_action()`
```gdscript
var provider: ResourceProvider = message.target.get_node_or_null("ResourceProvider") as ResourceProvider
if provider != null:
    a_actor.commander.population_max += provider.population_provided
```
**Used for:** Crediting the captor's population max when capturing a structure.  
**If null:** Capture completes; captor just doesn't receive a population bonus.  
**Verdict:** ✅ Legitimate optional. Not every structure has a ResourceProvider; capture works without one.

---

## `scripts/interface/rts_controller.gd`

### Line 191 — `sprite` in build preview setup
```gdscript
var sprite := source.get_node_or_null("Sprite") as Sprite3D
if sprite != null:
    var ghost := sprite.duplicate() as Sprite3D
    ghost.modulate.a = BUILD_PREVIEW_ALPHA
    _build_preview.add_child(ghost)
```
**Used for:** Extracting the structure's sprite to create a translucent placement ghost.  
**If null:** No ghost rendered — the placement cursor is invisible.  
**Verdict:** ⚠️ Borderline. An invisible build cursor is a bad UX and probably a scene misconfiguration rather than a legitimate state. Every buildable structure should have a `Sprite` child. Consider a `push_warning` when null so it surfaces during development.

---

## `scripts/maps/terrain/heightmap_mesh_generator.gd`

### Line 52 — `mi` in `_apply_to_instance()`
```gdscript
var mi: MeshInstance3D = get_node_or_null("GeneratedMesh")
if mi == null:
    mi = MeshInstance3D.new()
    mi.name = "GeneratedMesh"
    add_child(mi)
mi.mesh = mesh
```
**Used for:** Lazy-creating the MeshInstance3D that displays the terrain mesh, or reusing it if it already exists.  
**If null:** Node is created on the spot.  
**Verdict:** ✅ Legitimate optional. This is the idiomatic "create-or-update" pattern; `get_node_or_null` is exactly right here.

---

## Summary

| Verdict | Count | Locations |
|---|---|---|
| ✅ Legitimate optional | 19 | entity.gd ×6, commandable.gd ×6, selectable.gd, weapon.gd, command_context_parser.gd, capture.gd, rts_controller.gd (partial), heightmap_mesh_generator.gd |
| ⚠️ Borderline | 2 | production.gd:46 (`_train_bar` path set but node missing), rts_controller.gd:191 (invisible build cursor) |
| 🚨 Likely should be required | 4 | entity.gd:97 (`Body` always required), movement.gd:36 (nav agent missing = silent no-move), production.gd:82 (`TrainBarFill` in known-present bar), projectile.gd:17 (silent zero-damage projectile) |
