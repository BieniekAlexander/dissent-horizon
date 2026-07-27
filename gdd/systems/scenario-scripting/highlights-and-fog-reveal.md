---
title: Highlights and fog reveal
type: system-note
---

# Highlights and fog reveal

*Design note for [Dissent Horizon](../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

## Highlights (`EventHighlight`, `Condition.highlight_*`, `ScenarioHighlight`)


A highlight does not describe itself — it asks the trigger's Conditions what they are about, via two virtuals on `Condition`:
- `highlight_entities(manager) -> Array[Entity]` — things to mark with a ring.
- `highlight_shapes(manager) -> Array[HighlightShape]` — ground footprints to paint.

The rule that makes this work without authoring: **a check wanting FEWER of something marks the things** (`AT_MOST` on `ConditionUnitCount` / `ConditionStructureCount` returns the live matches, which disappear as they die); **a check wanting MORE of something marks the place** (`AT_LEAST` returns no entities, and `RegionAwareCondition.highlight_shapes` supplies the region instead). `ConditionUnitSelected` is the exception that marks candidates in the unmet state — the units exist, the player just hasn't clicked one.

`HighlightShape` (`scripts/scenario/highlight_shape.gd`) is the value type between the two: a circle or a rotated rect on XZ, built from a bound `CollisionShape3D` or from a grid cell. Its `rotation_y` is a **3D yaw** (`Basis(UP, yaw)`), not a 2D rotation — see `_local_to_world_xz`, which exists so a painted footprint is exactly the prism `RegionAwareCondition.region_contains` tests.

## Opening the fog (`EventRevealRegion`)


One event, two modes, because the difference is easy to get wrong: **explored ground is drawn, but `fog.gd` only shows an entity whose fog pixel is FULLY clear.** So marking a region explored un-shrouds the terrain and leaves everything standing on it invisible — no use at all for revealing an objective.

| `clears_fog` | Does | Cost | Use for |
| --- | --- | --- | --- |
| off (default) | marks the ground explored | instantaneous, no node | sketching in map the player has heard about |
| on | places a standing vision source | spawns a `Scout` per circle | showing the player what is THERE |

The vision source is a `Scout`: invisible, unselectable, collision-free, its `VisionRange` cylinder clearing fog for its owner. Spawned directly (`initialize` → position) rather than through `Map.add_entity`, whose unit-placement path samples a collision radius the Scout deliberately hasn't got; `EventRadarScan` does the same for the same reason. `lifespan_frames < 0` is permanent — Radar Scan is the temporary version of the same mechanism, and `_validate_property` greys the field out in explored-only mode where nothing persists.

Either mode opens a circle at the event's own position, or one over every Node3D in `target_group`. A group rather than a list of node references because the set is usually a category the scene already names ("the camps still standing"), so a member added, moved or removed later needs no change to the event.

**`_resize_vision` duplicates the shape before writing the radius** — a PackedScene's sub-resources are shared across its instances, so writing in place would resize every other Scout in the game.

## Objectives are green, in both views


`ScenarioHighlight.OBJECTIVE_COLOR` is the one constant behind it — a vivid spring green, chosen so it can't be mistaken for team 3's dark `Color(.1,.6,.1)`. `EventHighlight.color` defaults to it; override per node only when a highlight means something other than "this is your objective".

The **minimap draws the same targets in the same colour**. Every live `ScenarioHighlight` joins the `scenario_highlight` group, and `Minimap._draw_objective_markers()` reads that group — so the minimap knows nothing about triggers, conditions or objectives, only that something is highlighted and what colour it picked. Marked entities get a **hollow** ring (`OBJECTIVE_RING_RADIUS`) so the unit's team dot still shows through the middle: the marker means "this one matters", not "this one is green". Marked regions get their perimeter traced.

Both views share `HighlightShape.perimeter_points(spacing)` — four corner points are not a rectangle once anything is sampled along them, whether you're draping onto terrain (world) or filling pixels (minimap).

Deliberately **not** fog-gated: the world painter already rings these targets through terrain, so hiding them on the minimap would just make the two disagree, and an objective naming a target the player cannot find is not an objective.

The HUD checklist colours by SCOPE instead (see §Objectives are a SCOPE): green for a primary, amber for a secondary, red for a failure condition, whether or not the row is done. The colours are exports on `ObjectiveView`, not `ScenarioHighlight` constants — the checklist's green answers "is this required or optional?", which is a different question from the world markers' "is this the thing the objective means?", so the two are deliberately not the same value.

---
