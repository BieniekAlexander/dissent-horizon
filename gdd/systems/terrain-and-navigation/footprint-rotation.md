---
title: Footprint rotation
type: system-note
---

# Footprint rotation

*Design note for [Dissent Horizon](../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

**PLANNED 2026-09-30.** Indexed as [`deferred.md`](../../deferred.md) 2.4. Nothing here is built.
**How the player asks for a rotation is deliberately not planned yet** — the control scheme is about
to change, so §The seam is the interface the controller will call, and no key, button or gesture is
proposed. Everything else is.

## What exists

Rotation is a parameter nothing reads. `Map.add_structure(structure, world_center, _a_rotation, …)`
takes it underscore-prefixed and ignores it; `Entity._auto_initialize` passes `0`.

The footprint itself is already **rotation-shaped**, which is why this is smaller than it looks:

- Every footprint function on `Map` — `footprint_origin`, `footprint_cells`, `footprint_centroid` —
  takes the dimensions as an ARGUMENT (`a_dims: Vector2i`) and reads nothing from the piece. So the
  Map API needs no new signature: a rotated footprint is the same call with swapped dimensions.
- The **dimensions** come from one place, `Structure.dimensions`, written by the spec importer from
  the doc's `footprint:` (`SceneSync._sync_footprint`). The doc's value is the footprint at rotation 0.
- `Entity.hull()` already builds its rectangle from the TargetShape's **global basis**, so a piece
  whose root is yawed a quarter turn already measures every range from the rotated rectangle. Ranges,
  aggro, reach and interaction need no change.
- Facing is the root node's `rotation.y` (`Movement.get_facing`, `Commandable._drive_mesh_visual`),
  and `MeshVisual`, the selection shape and the baked placeholder mesh are children that inherit it.

What is **not** rotation-shaped is every caller that reads `Structure.dimensions` and hands it to one
of those functions. About twenty sites do (`build.gd` ×8, `map.gd` ×8, `energy_extractor.gd` ×4,
`rts_controller.gd`, `entity.gd`, `deployment.gd`, `commander.gd`, `bot_economy.gd`,
`footprint_visualizer.gd`, `producer_affinity_indicator.gd`, `scenario_highlight.gd`,
`debug_placement.gd`, and the `terrain_snap` editor plugin). Rotation is those sites agreeing, which
is the same discipline `Map.footprint_origin` was introduced to enforce for parity.

## Who it matters to

Rotation changes the cells a piece claims only when the footprint is **not square**. Today that is
`nt_building_long` (3×5), `nt_building_large` (8×5), `cl_airField` (6×4) and `an_tech2` (1×4);
every other piece is square, for which a rotation is purely visual and directional. Any future
non-square piece, and every neutral-building variant a player can build as `an_infrastructure`
(square 4×4, long 3×5), is affected the same way. Rectangles only: irregular footprints are still
the open item in [structure-footprints](structure-footprints.md) §2 and rotate by the same rule
when they arrive (§Open, last item).

## Decisions

**Rotation is a QUARTER TURN count, an `int` in 0…3, held on `Structure` as `quarter_turns`.**
Not a float angle and not a free yaw: the grid is registered in integers, and a float `rotation.y`
that drifts by an epsilon must never change which cells a building holds. `Structure` writes the
root's `rotation.y` from it when the piece is registered; the visual follows the count, never the
other way round. 0 is the unrotated doc footprint.

**Dimensions are oriented in one function.** `Structure.oriented_dimensions(dimensions, quarter_turns)`
(static, pure) returns `Vector2i(dimensions.y, dimensions.x)` for an odd count and `dimensions` for an
even one. It is the ONLY place that swaps, exactly as `Map.footprint_origin` is the only place that
resolves parity. A caller that needs the footprint asks for oriented dimensions and passes them on;
none re-derives them.

**Rotation is state of the placed piece, not of the tool.** The doc's `footprint:` stays the rotation-0
size and `Tool` stays rotation-free. What travels is the count: on the `CommandMessage` (as
`quarter_turns`, beside `xz_position`), on a planned structure (a blueprint remembers how it was
laid), and on the `Structure` once registered. An `int` in an order is also what a replay stream
records ([recording-and-replay](../commands/recording-and-replay.md)), so this adds no float to the
determinism surface.

**A rotation is chosen at placement and never changed afterwards.** No rotate-in-place order. A
registered footprint holds cells and, possibly, units and navmesh; re-registering it is a rebuild
the game has no reason to offer. This also keeps `structure_cell_map` (registered cells) and
`quarter_turns` trivially consistent.

**A piece owns its orientation, so things orient with it.** The airfield's `Runway` marker, its
docking pads, and any door or side a piece has are children of the root, so they turn with it and
nothing about them is rewritten — but nothing may hard-code a world direction for them either.
Runway geometry and pad layout are audited for that in slice 2.

## The seam

The one interface a control scheme has to know: **`CommandMessage.quarter_turns`, and a preview that
shows the footprint at that count.** Whatever the player does to choose the number, the ghost redraws
from `Structure.oriented_dimensions` and `Build` refuses or accepts against the same. The controller
holds one `placement_quarter_turns: int`; whether it survives between placements, resets per tool, or
is remembered per piece is a controls decision and is left open on purpose.

## Slices, in order

Each slice ends green and is useful alone. All tests build their own fixtures (a synthetic Map, a
synthetic structure) — none reads an authored scene, per CLAUDE.md §A unit test does not assert facts
about authored content.

1. **The core, headless.** `Structure.quarter_turns`, `oriented_dimensions`, and `add_structure`
   honouring its (now un-underscored) rotation argument: registers the oriented cells, centres on the
   oriented centroid, and writes the root yaw. `Structure.valid_placement`, `EnergyExtractor`'s
   overloads and `Entity.valid_placement` take the count. Tests: every count over an odd×odd, an
   even×even and a mixed (2×3) footprint; **idempotence** (snapping, reading the position back and
   snapping again yields the same origin — the property `footprint_origin` documents); an out-of-bounds
   rotated footprint is refused; `Hull` of a rotated piece equals the oriented rectangle.
2. **Order and gates.** `Build` and its helpers (`_tool_dimensions`, `_build_reach`, the planned-footprint
   comparison, `_placement_keeps_navmesh_access`) all read oriented dimensions; `Commander.planned_footprint_cells`
   and `Deployment` do the same. `NavPlacement` needs no change of its own — it already takes cells —
   but its tests gain rotated cases, including a rotation that seals a producer in and one that
   frees it. The airfield's runway and pads are audited for world-direction assumptions.
3. **Preview and scene authoring.** The ghost, `FootprintVisualizer`, `ProducerAffinityIndicator`,
   `ScenarioHighlight` and the `terrain_snap` plugin use oriented dimensions. A scene-placed structure
   takes its count from its own `rotation.y` in `Entity._auto_initialize` (rounded to the nearest
   quarter turn; a yaw more than a few degrees off a quarter turn is a `push_warning` and is
   snapped, since the grid cannot hold anything else) — which is what makes rotation authorable in
   the editor before any player-facing control exists.
4. **The bot.** `BotEconomy._find_build_spot` considers both orientations of a non-square footprint
   and scores them like any other candidate; **mirror equivariance** (`tests/test_BotPlacementEquivariance`)
   extends to rotation: mirroring a map maps a quarter-turn count `t` to `−t` (mod 4).
   Until then the bot places at 0 and is correct, only less flexible.
5. **The control, and replay.** Wire the controller to the seam once the new controls exist; record
   the count in the order stream if 2.46 has landed.

## Interactions to get right, not to defer

- **An extractor follows its site.** `Map.add_structure` already takes the site's cells when an
  extractor stands on one, on the rule that the two footprints are equal. An extractor placed on a
  site inherits the SITE's count and refuses any other; a rotation is not offered to the player for it.
- **Converting a neutral building** (`an_infrastructure` built over an `nt_building_*`) keeps the
  building's existing orientation. The player's rotation is ignored for a conversion — it changes
  an owner, not cells.
- **A captured or garrisoned neutral structure keeps its rotation**; ownership never re-registers it.
- **Odd swaps and parity.** Rotating a 2×3 makes it 3×2, which centres differently (`footprint_origin`
  rounds each axis by parity). The ghost may therefore hop by half a cell when rotated about a fixed
  cursor; that is correct — it is where the structure would land — and slice 1's idempotence test is
  what proves the ghost and the placed piece agree.
- **The map tools.** `Map.mirror_map` / `shift_map` reseat entities; a rotated structure must keep its
  count through a shift and reflect it through a mirror (slice 4's rule). Neither is exercised until
  a rotated structure exists on an authored map.

## Open

**TODO — is a 180° turn a real choice?** It claims the same cells as 0°, so it changes only which way
the piece faces (an airfield's runway, a directional model). If art is not directional and nothing
else faces, offering it is noise. Leaning: allow all four in the model (it is free), and let the
CONTROL decide how many are offered.

**TODO — two-form pieces (deploy).** A deployed piece takes its footprint where the unit stands, and a
unit has an arbitrary `rotation.y`. Leaning: deploy at the unit's facing rounded to the nearest
quarter turn — "the way it was pointing" — with the deploy preview showing the result.

**TODO — irregular footprints.** Out of scope here, but the rule is already known: rotate the offsets by
`(x, z) → (z, -x)` and re-normalise to non-negative (the proposal in
[structure-footprints](structure-footprints.md) §12), which reduces to `oriented_dimensions` for a
rectangle.

**TODO — directional art.** Whether the game's models are directional decides how much rotation is
worth to a player who is not laying out a wall. Not a code question; it belongs with the art pipeline.
