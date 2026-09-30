---
title: Piece vocabulary — what a piece is called
type: system-note
---

# Piece vocabulary

*Design note for [Dissent Horizon](../../../CLAUDE.md). The naming half of
[composition-rework](composition-rework.md).*

Most identifiers still use the old names; §Where today's code disagrees lists every place
that has not caught up yet.

---

## Why a vocabulary at all

Under composition the code never needs a noun, because every check is a component predicate.
People and agents do need nouns. "An uncommandable, attackable, airborne, sighted piece" is
accurate and unreadable. So the vocabulary has two layers:

1. **Facets** are adjectives. Each one is **exactly one predicate over components or
   state**, and an agent writing code turns the word into that predicate and nothing else.
2. **Nouns** are each a **named conjunction of facets**. The nouns **partition** the roster:
   at any tick every piece is exactly one of them. Facets then add detail to the noun ("an
   attackable token", "an immobile unit", "a feature that is not an obstruction").

**A noun is never tested directly in code.** It is shorthand for its definition, and the code
tests the definition. That rules out the old failure, where `unit` meant "inherits
`unit.tscn`" and a piece could not be both a unit and something else.

**Nouns follow ACTIVE facets, not the component list.** A transformer is a structure while its
footprint is live and a unit while its locomotion is live. It changes noun and keeps its
identity. Composition-rework §Step 1 builds that switch.

---

## The partition

Two questions place every piece: **is it an Actor** (does it take orders)? and **is it a
fixture** (does it claim terrain-grid cells)?

|                  | **fixture**   | **figure** |
| ---------------- | ------------- | ---------- |
| **Actor**        | **structure** | **unit**   |
| **not an Actor** | **feature**   | **token**  |

- **Actor**: a piece that holds a command queue its owner can select and fill. This is today's
  `Commandable`. The adjective is still *commandable*.
- **Fixture**: a piece that claims terrain-grid cells. It is fixed in place and cannot move
  while it is one. A **structure** is a commandable fixture (a barracks, an extractor, a
  deployed transformer). A **feature** is an uncommandable one (an extraction site, a
  shelter). **"Building" is not a category.** It is the name of a family of specific pieces
  (`nt_building_square`, `_long`, `_shack`, `_large`), recognised as one by the `neutral_building`
  group they carry.
- **Figure**: any piece that is not a fixture. A **unit** is a commandable figure. A **token**
  is an uncommandable one (a Recon Drone, a beacon, a rocket).

**A unit does not have to move.** A cannon mounted on a scripted train is an *immobile unit*.
Mobility is a facet, not a noun.

### Obstruction is a kind of fixture

An **obstruction** is a fixture whose cells are removed from the navmesh, so units cannot walk
there. **Only a fixture can be an obstruction**, so obstruction is only ever computed for a
fixture. A figure that blocks movement does so through avoidance, which is a different
mechanism. Both structures and features can be obstructions, and neither has to be: the
extraction site is not one (`Structure.is_obstruction`,
[map-composition](../terrain-and-navigation/map-composition.md) §Occupancy and obstruction).

A fixture's cells are either its OWN (**occupant**: `cell_grid` points at it) or a **host's**
(**overlay**: an extractor on its site). Both are fixtures.

### Emission is an origin, not a noun

An **emission** is a piece that an **emitter** put into the world: a unit or a token. A rocket
is an emitted token. A Brood Lord's broodling is an emitted unit. Nobody needs to call a
broodling "an emission", but the term is correct for it, and the emitter interface
(composition-rework §Emitting, as one interface) handles both the same way. Phases (the
emission phase list) do not decide the noun.

---

## Facets

| Facet | Predicate | Today's test |
|---|---|---|
| **piece** | an `Entity` with a spec doc (`kind: Entity`) | `Entity` with a non-empty `id` |
| **owned** / **neutral** | its commander is a player / the world | `commander_id > 0` / `== 0` |
| **commandable** (= Actor) | holds a command queue its owner can select and fill | `is Commandable` *and* `Selectable.selectable_by_player` |
| **selectable** | can be clicked or boxed, if only to inspect it | `Selectable.select()` succeeds |
| **fixture** | claims terrain-grid cells | `Entity.structure_is_active()` |
| **obstruction** | a fixture whose cells leave the navmesh | `Entity.is_grid_obstruction()` |
| **mobile** | has live locomotion *and somewhere it can go* | `Entity.movement` non-null, speed > 0 |
| **airborne** | is on the air targetable layer right now | `is_air_target()` |
| **targetable** | a weapon's target mask can lock onto it | `targetable_layers() != 0` |
| **attackable** | targetable *and* can take damage | `Entity.is_attackable()` |
| **sighted** | contributes fog reveal for its owner | in the `"los"` group (has `VisionRange`) |
| **detecting** | exposes stealthed enemies in a radius | has a `DetectionRange` |
| **garrisonable** | can hold other pieces | has `Garrison` |
| **expiring** | removes itself after a fixed time | has a `Lifespan` |

**Facets are independent on purpose.** *Selectable* is not *commandable*: an extraction site
can be clicked to read it, and an enemy unit can be selected but not ordered. *Targetable* is
not *attackable*: the extraction site has a ground target layer and no `Defense`.

**Commandability belongs to the piece. Authority belongs to the owner.** "Yours to command"
means *commandable and owned by you*. It is not a separate facet.

### States, which are not facets

A state changes during the piece's life and never changes its noun: **planned** (placed, not
started, with no target layer), **under construction**, **built**, **held** (garrisoned or
interned: off the tree and still alive; see
[garrison-and-transport](../combat/garrison-and-transport.md)), **dead**. **Emitted** is an
origin, so it is not a state either.

---

## The roster, classified

These are the pieces whose classification was unclear.

| Piece | Noun | Facets worth naming |
|---|---|---|
| Recon Drone (`nt_aircraftLight_recon`, Scan's eye) | **token** | airborne, attackable, sighted; detecting at Scan 2+; expiring at Scan 1–2 |
| Extraction site | **feature** (occupant) | selectable; targetable but not attackable; walkable — not an obstruction |
| Extractor | **structure** (overlay) | attackable; the obstruction over its site |
| Shelter | **feature** | garrisonable, selectable |
| Beacon | **token** | owned; sighted from Drop 2; expiring until Drop 3 |
| Rockets, bullets, lazer, clouds | **token** (emitted) | — |
| Brood Lord's broodling (planned) | **unit** (emitted) | expiring |
| Kamikaze (`an_aircraftLight_antiMech`) | **unit** | — |
| Transformer (planned) | **structure ↔ unit** | the noun follows the active component |
| Garrisoned / interned unit | **unit** (held) | — |
| Fog pseudo-unit (planned) | **token** | sighted, expiring |
| Train carrying a cannon (planned) | train: mobile **token**; cannon: immobile **unit** | — |
| Lithium pond | not a piece | a `WaterBody` is terrain; only its budget might become a piece ([water-bodies](../terrain-and-navigation/water-bodies.md) §The lithium pond) |
| Status effects, `HealAOE` | not pieces | nodes under a piece |

---

## Where today's code disagrees

- **The groups follow the partition** (split 2026-09-29): the importer derives `"fixture"` for
  every fixture and adds `"structure"` only when it also takes orders, so the shelter and the
  extraction site are fixtures and not structures. Readers ask the one they mean — grid
  teardown, footprint reach and the fog memory of seen buildings ask `"fixture"`; production,
  rally and construction state ask `"structure"`.
- PLANNED: **Two class names are not in the code yet.** `Commandable` becomes `Actor`, and the
  `Structure` component becomes the fixture component — renames done at step 4.
- **The Recon Drone is a HOVERING aircraft with speed 0** (decided 2026-09-29): `Aerial` puts
  it in the air and on `TARGETABLE_AIR`, and its speed-0 `Movement` holds the hover. It never
  receives an order, so it never moves. See composition-rework §Locomotion is bigger than
  `Movement`.
- TODO: **The Recon Drone's root is `Commandable`** though it is not commandable (its doc says
  `commandable: false`, and its `Selectable` refuses selection). The class gives it the
  stealth-detection tick. Under composition that tick
  belongs to whichever piece has a `DetectionRange`.
- **Fog hides every piece under it, with no exceptions** (decided and built 2026-09-28). The
  `"piece"` group does not hold beacons or emissions, so they are hidden by their own pass,
  `Fog._apply_figure_visibility`, over `Beacon.GROUP` and `PhasedLocomotion.EMISSION_GROUP`:
  - **Hidden means hidden to the logic too.** `Entity.is_visible_to` asks fog and stealth, and it
    is the predicate any path that acts on an opponent's piece must ask; a fogged beacon is
    untargetable. (Making a beacon targetable is not the design; if it ever were, it would come
    from giving the beacon a small sight of its own, not from exempting it.)
  - **Visible the moment it enters sight**, by the pixel under it: an emission fired from the
    fog appears as it crosses into sight, and an impact in sight is seen though the flight was
    not.
  - **A beam spanning the fog edge is drawn partially** — see
    [projectiles](../combat/projectiles.md) §Visuals.
  - **Fog and stealth both apply** to a beacon, on different nodes so they cannot fight: fog
    hides the root, stealth fades its `MeshVisual` (`Beacon._process`).
