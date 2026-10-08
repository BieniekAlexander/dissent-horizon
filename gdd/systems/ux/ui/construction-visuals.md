---
title: Construction visuals
type: system-note
---

# Construction visuals

*Design note for [Dissent Horizon](../../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

## Two channels, not one four-step scale

`Actor._apply_construction_visuals` writes the model on two INDEPENDENT channels:
**opacity**, how far along the construction lifecycle the piece is, and **shade**, whether
it has been paid for. They are separate because they answer different questions and vary
independently — a blueprint can be funded or not at the same lifecycle point.

These are the CONSTRUCTION channels only. `StatusVisuals` writes a separate pair for the
piece's CONDITION (stealth, status effects) and `MeshVisual` multiplies the two together, so
an event-driven write here is never overwritten by that per-frame one.

The under-construction fade is a **step, not a ramp** on `build_progress`: a half-built
structure should read as "under construction", not as "almost invisible" the moment it is
placed.

## Construction opacity


How solid a structure is drawn says how real it is. The three steps are `MeshVisual.OPACITY_PLANNED` / `OPACITY_CONSTRUCTING` / `OPACITY_BUILT` (0.2 / 0.5 / 1.0) — one set of constants, so a structure reads the same wherever it's drawn:

| State | Drawn at | Owned by |
| --- | --- | --- |
| **Planned** — a blueprint (a real entity, see below), or the ghost under the cursor while aiming a Build | 0.2 | `Actor.construction_opacity`; the cursor ghost is `RTSController._add_ghost_visual` |
| **Constructing** — placed, collidable, unfinished | 0.5 | `Actor._apply_construction_visuals`, driven by `build_progress_changed` |
| **Built** | 1.0 | same |

The fade is a **step, not a ramp** with `build_progress`: a half-built structure should read as "under construction", not as nearly invisible. `MeshVisual.set_opacity` also drops the model's shadow while faded (a translucent building that still casts a filled shadow reads as solid).

**Opacity is one of TWO channels.** The other is `MeshVisual.set_shade` (`SHADE_AWAITING_FUNDS` 0.35 / `SHADE_NORMAL` 1.0), an RGB multiply that darkens a blueprint whose purchase is still PENDING — a build the commander has committed to but can't pay for yet (`Actor.awaiting_funds` / `construction_shade`). Two channels rather than one four-step scale because they answer different questions and vary independently: a blueprint is at the same point in the construction lifecycle whether or not it has been paid for. `_reapply` composes `albedo = base × tint × shade` on RGB and `base.a × opacity` on alpha, so shade never affects transparency and the team tint survives underneath both.

**And each of those two is itself one of a PAIR** — the construction channel written here, and a STATUS channel written by `StatusVisuals` for the unit's condition. See §Condition visuals; the composition is `effective_opacity()` / `effective_shade()`.

`awaiting_funds` is written in exactly two places: `Build.plan_structure` seeds it from `transaction.is_pending()`, and `PurchaseTransaction.fund()` clears it. Seeding from the transaction's live state is load-bearing — `submit_purchase` runs BEFORE `plan_structure` and `ProductionQueue.submit` drains synchronously, so an affordable build is already FUNDED by the time its blueprint exists, and `fund()` will never fire again to correct a wrongly-set flag.

## The placement grid

While a structure is being placed — by a Build order, or as a start-of-game deployment drop, which
registers on the grid just the same — the terrain grid is traced under it (`PlacementGridOverlay`, drawn
by `RTSController._update_placement_grid`), after StarCraft II's:

- **The footprint** — each cell outlined and washed green where it can be built on and red where
  it cannot, judged per cell by the same rule the order uses (`Fixture.cell_admits_structure`),
  plus the planned-site rule: a cell a planned building on our side has claimed is red
  ([construction](../../commands/construction.md) §A plan claims its site).
  An extractor is judged as a whole, since it overlays a site or takes a pond, so its cells share
  the order's verdict.
- **Three cells around it**: one at full strength, then two fading out fast. A hard-edged box
  would read as a boundary; the grid is context, not a limit.
- **The dominion claim, under ANY structure being placed** — every tile the placer's Opticons
  claim, washed in (`DominionRoute.claim_layer`), because building on a claimed tile costs income
  whatever goes there. Ordered-but-unfinished pieces count, drawn as pending (README §Pending
  pieces are shown, as pending): a planned or rising Opticon's claim is drawn fainter, and a
  paying tile a planned building will cover is drawn in the loss colour.
- **A piece whose worth is the ground it claims** — the Opticon — has the grid extended over its
  whole claim (its vision), with every cell that would earn nothing washed grey: claimed by
  another Opticon, standing or pending, or under one of your fixtures, standing or planned
  (`DominionRoute.site_claim`). A future ground-claiming piece needs no HUD work.

### Aimed at a building it would convert

Building the Anarchical infrastructure on a neutral building converts that building instead of
placing a new one. While it is aimed at one, no ghost and no placement grid are drawn — the
new-structure verdict (footprint, red or green) would say something false about a building that is
already there — and the target wears the same marker an aimed single-unit ability does. The energy
bar previews the conversion's own, discounted price, not the price of building the form new.

### Range rings while placing

Range circles ride along, around the ghost: every weapon's reach and detection always, and
vision too while the verbose key is held — what a defence will cover from here is the question
placing one asks. They are the shapes the piece will actually use, read off its scene.

Beside each of those reaches, the same KIND of reach of every structure on our side that it
would overlap from here — the coverage this one joins. Only overlapping ones, and only kinds
the placed piece has: drawing all of them would put a web of circles over the whole base.
Standing, rising and planned structures all count; one not up yet draws its ring dashed
(README §Pending pieces are shown, as pending).

TODO: the colours are placeholders — Alex is revisiting the game's palette (`PlacementGridOverlay`'s
constants).
