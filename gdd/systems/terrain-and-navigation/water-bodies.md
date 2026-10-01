---
title: Water bodies
type: system-note
---

# Water bodies — a level, a basin, and what that costs you

*Design note for [Dissent Horizon](../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

The other map features are in [map-composition.md](map-composition.md).

---

## Water is a height and a plane

**A body of water is a depression in the terrain plus a number.** It is not a kind of ground,
it has no physics, and nothing about it is painted on a cell. `WaterBody` holds a *level*;
`WaterBasin` floods outward from a seed cell to everything the terrain lets that level reach;
everything else — which cells are covered, how deep each is, the surface mesh, which cells
leave the navmesh — is derived from those two facts every time the map loads.

The reason it is a level rather than a tile type is a single property: **a painted tile can
contradict the geometry and a depth cannot.** Nothing stops a brush painting `Water` onto a
hilltop. Nothing can paint a lake onto a hilltop under a water level.

The reason it is a *seed cell and a level* rather than a stored cell list is
`~/.claude/CLAUDE.md` §10: the cell list is a derived artifact, and re-sculpting the terrain
under a body re-floods it correctly instead of stranding a footprint that no longer matches
the ground. **Nothing about the water is saved except the four authored values** — seed cell,
level, energy, charge colour.

### What the fill does, exactly

Every cell's height is the **mean of its four corners** — the surface at its centre, which is
where a unit stands and what the water plane is measured against. A cell is flooded when that
mean is strictly below the level. The fill is **4-connected**, matching how the navmesh
stitches cells: two pools meeting only at a corner are two bodies.

Two things are walls, and they are the same kind of wall:

- **Dry ground.** A cell at or above the level stops the fill.
- **The edge of the play area.** Water cannot leave the map, so the boundary holds it. A fill
  that reaches it is not an error; it is a flooded lowland rather than an enclosed pond, and
  the authoring tool says which one you are about to make.

**The seed cell is admitted whatever its own height.** The level an author picks is the height
of the point they are pointing at, so the cell under the cursor is submerged by approximately
zero and would otherwise refuse to start its own fill. What that costs is a basin that can be
empty, which `WaterBasin.is_valid()` reports and the tool refuses to build from.

---

## Passability falls out of depth

One project-wide constant — `WaterBasin.WADE_DEPTH`, 0.5 — and one level per body:

| Cell | Rule | Result |
|---|---|---|
| **Dry** | at or above the level | ordinary ground; the usual steep / flat rules apply |
| **Shallow** | submerged by ≤ `WADE_DEPTH` | **passable.** No speed change, no status effect, no navigation difference at all |
| **Deep** | submerged by > `WADE_DEPTH` | **impassable.** No navmesh is baked under it |

`WADE_DEPTH` is the deepest water a unit walks through, not the shallowest it cannot — exactly
`WADE_DEPTH` is wadeable, the same way `MAX_SLOPE_DIFF` is.

**Submersion is its OWN impassability bit** in `TerrainGrid` (`_SUBMERGED`), beside `_STEEP`,
`_BUILDING` and `_BLOCKED` rather than folded into any of them. Two reasons, and the first is
mechanical: the water layer is republished *as a whole*, over every body at once, whenever any
body changes — a shared bit would have the republication silently clear the tile-type and
out-of-play mask. The second is the one `tile-types.md` already gave: a future movement class
may ignore water and not cliffs, and it cannot if they are the same bit.

`Map.refresh_water()` is what publishes it, and it takes the union deliberately: the grid holds
one mask, so telling it about one body in isolation is not expressible. It is cheap because
water is authored — it runs at load and on an authoring edit, never in the game loop.

**Nothing prunes the navmesh islands a lake creates.** A ground order into an unreachable
component is left exactly where it was clicked; see
[navigation-and-pathing.md](navigation-and-pathing.md) §An unreachable destination is left
alone.

---

## What may be built in water

**`Structure.allow_submerged` is the whole rule.** A structure that declares it may stand in
shallow water, on the solid terrain underneath, partly submerged. A structure that does not is
refused. Deep water is granted to nothing at all: it is impassable ground, and impassable
ground holds nothing.

A flag on the piece rather than a list of piece ids in the placement code, because the question
is a property of the piece. Today exactly one piece sets it — `nt_extractor` — and admitting a
second is a checkbox in that piece's scene, not an edit to a rule.

The ordinary flatness requirement still applies, and that has an authoring consequence worth
stating: **a pond floor has to be sculpted flat before anything can be built on it.** `is_flat`
wants four identical corner heights, which the brush's Set mode produces and a feathered slope
does not.

---

## The lithium pond: the same extractor, a different reservoir

A charged body of water is a lithium pond — thematically brine, mechanically a finite energy
budget. It is worked by **the same `Extractor` structure an extraction site is**, because a
second collector type would be a sibling of that abstraction rather than an instance of it
(`~/.claude/CLAUDE.md` §1.3). What differs is behind the extractor, not in front of it:

|  | Extraction site | Lithium pond |
|---|---|---|
| Host geometry | a 2×2 structure; the extractor must sit **concentric** on it | a whole basin; the extractor stands anywhere shallow in it |
| Grid | the site occupies the cells; the extractor **overlays** it | nothing occupies the cells; the extractor **obstructs** like any structure |
| Supply | infinite | `WaterBody.energy`, finite, never replenished |
| Rate | the extractor's own `energy_rate` | `POND_RATE_MULTIPLIER` (4) × that rate |

Those two placement cases are why `EnergyExtractor.valid_placement` asks a different question
from `Structure.valid_placement` and is used *instead of* it: an overlay's target cells are
legitimately occupied, so the generic empty-cell rule can never pass for one.

**The budget lives on the pond, not on the extractor** — otherwise destroying and rebuilding
the extractor would refill the pond. `EnergyExtractor.reservoir` points at the body; a null
reservoir is the inexhaustible default an extraction site keeps. A drained pond simply returns
zero and the extractor stops earning; nothing has to notice and tear anything down.

**Any number of extractors may work one pond, and they share its budget.** That is what makes
a pond's *area* worth something — it is the fast, contested half of the energy economy
(`gdd/setting/resources.md` §Lithium ponds), and racing a neighbour to the bottom of one is the
intended shape. It is also simply what the model already says: the pond is a reservoir, not a
socket.

A hand-authored pond's charge is a flat number (`WaterBody.NOMINAL_ENERGY`, 2500). A GENERATED
pond's is `cell_count × richness_factor` ([map-generation.md](map-generation.md) §3); the two
rules are deliberately separate.

---

## One extractor per body

**A body admits exactly one extractor** (`WaterBody.extractor`, `has_extractor()`), refused at
the same place the site rule is: `EnergyExtractor.valid_placement`, whose ExtractionSite branch
has always answered `(host as ExtractionSite).extractor == null`. The pond branch had no
counterpart until 2026-09-12 and took as many extractors as would fit.

**The reason differs from a site's.** A site is inexhaustible and overlaid — a second extractor
has nowhere to stand. A pond is a FINITE charge, and extractors in it occupy their own cells, so
a second one physically fits; what it would do is split the same remaining `energy` between two
structures and drain it twice as fast for the same total. Nothing is gained and the pond is gone
sooner.

The claim is taken by `Extractor.bind_water_body` and released by `Extractor._on_death`, so a
destroyed extractor leaves its pond workable again — the same lifecycle as the site claim
beside it.

`has_extractor()` VALIDATES rather than trusting the field, and the field is untyped, for the
reason `~/.claude/CLAUDE.md` §A freed object cannot be passed to a typed parameter gives: a
typed read of a freed object errors before any guard can run, and a body outliving a missed
release must not be stranded unworkable for the rest of the match.

**`is_workable()` is the question anything SHOPPING for a pond asks** — charged, and unclaimed.
A drained pond is dry ground with a surface on it. Placement itself stays permissive about
charge; only the search filters on it.

**A claim is only taken when an extractor is PLACED, so the rule needs a second enforcement
point.** Two builders ordered at one pond before either arrives both pass the order-time check,
and the co-build guard in `Build.fulfill_action` sees only the target FOOTPRINT — a pond is many
cells wide, so the second builder's own cells are clear and it raises a duplicate. Observed on
`skirmish.tscn`: pond (55,104) finished a match with two extractors in it.

So `Build.fulfill_action` re-asks on arrival (`_target_pond_is_taken`) and ABANDONS the order —
there is nothing to co-build, because the other extractor is somewhere else in the same body.
The `ExtractionSite` half needs no equivalent: a site IS the footprint, so the existing guard
already catches it. The bot additionally declines to issue the second order at all
(`BotEconomy._ponds_under_way`), so a builder is not spent walking to a job that will be
abandoned.

Tests: `tests/test_WaterPlacement.gd` §One extractor per body and §Two builders, one pond.

## The node sits on its pond

**A `WaterBody`'s transform is DERIVED: `rebuild()` recentres the node on the middle of its own
basin, at the water's own `level`.** Before 2026-09-12 every body sat at the Map's origin, which
made a map with eight of them unreadable in the editor — eight identical gizmos in a heap,
none of them near the water they described.

**It is a gizmo, not geometry, and that is what makes it safe.** The basin is derived from
`seed_cell` and the terrain in GRID coordinates; the surface mesh pins itself to the MAP's frame
rather than this node's (`_rebuild_surface` says so in as many words); the submerged-cell
publication is cells. Nothing reads this transform, so moving it cannot move the water — and
`tests/test_WaterPlacement.gd` §The node sits on its pond asserts each of those separately,
precisely so that the day something DOES start reading it, the change is caught rather than
discovered as a pond sliding off its basin.

**Never saved** (`_validate_property` strips `PROPERTY_USAGE_STORAGE` from `transform`, which is
the property Node3D actually stores — `position` / `rotation` / `scale` are editor views of it).
A stored centre would be a second, stale answer to where the pond is the moment the terrain
under it is re-sculpted, which is the same reason the basin and the surface are not saved
either. It is read-only in the inspector for the matching reason: an author who dragged the node
would otherwise watch it snap back on the next rebuild with no indication why.

## How the surface is drawn

One quad per covered cell at the water level, built by `WaterSurfaceMesh` in the heightmap's
own frame so it lines up with the terrain with no transform of its own. **The only thing baked
into the geometry is depth**, as a 0..1 shade factor per corner; everything else is a shader
uniform, because everything else changes while the mesh does not.

- **Depth** ramps light blue to dark blue across `WADE_DEPTH`, so the colour boundary is the
  navmesh boundary — the shoreline a player reads is the line their units actually stop at.
  The ramp is spread over a band around the threshold so it reads as a shoreline; the
  classification behind it stays binary.
- **Charge** fades the whole surface toward the body's own `charge_color` — a pink, ochre or
  green picked from `WaterBody.CHARGE_COLORS` when the body is authored and *stored on it*, so
  a map does not change colour every time it loads. The fade tracks the remaining fraction of
  the pond's original budget, so a pond visibly drains back to plain water.
- **Fog** is pushed in by `Fog`, through `Map.fogged_materials()`. That function exists rather
  than `Fog` naming one node because **a surface left out of the list is silently unfogged** —
  the shroud stops at the shoreline and the lake stays bright. Any new world-geometry shader
  joins that list.

Corner depths are read from heightmap **corner** heights rather than from the per-cell means
the basin classifies with: adjacent quads share a corner, and a shared corner has to produce
one shade from both sides or the gradient creases along every cell boundary.

The bed under the water renders normally — it is meant to be seen through the plane. That is
free rather than arranged: the mesh generator's "impassable ⇒ black" rule keys off corner
spread and tile type, neither of which submersion touches.

---

## Water floods against `terrain_data`; the viewport draws `terrain_source_mesh`

**If those two disagree, the Water tool floods ground the author cannot see.** Found
2026-09-11 on `skirmish`: the bake said 0.70-0.85 across a patch the mesh drew flat at 1.00,
so three ponds were authored with levels of 0.86-0.92 — *below* the ground actually on screen.
They drew nothing at runtime, and once the terrain was re-baked they flooded **zero cells**,
because they had never been over a depression at all.

Nothing about the water was wrong. The pond is downstream of the bake, so a stale bake makes
every pond authored against it fiction.

`Map.source_mesh_bake_residual()` measures the drift (0.0 = the two agree). It is a whole
re-bake, so the Water brush measures it once on entering the mode — but then **refuses to
work at all until it is zero**: no preview, no placement, and the status line repeats the
reason on every mouse move rather than logging it once to a panel nobody is looking at.

```
STALE TERRAIN: terrain_data is 0.500 out from terrain_source_mesh — press Bake Terrain From Mesh
```

Refusing rather than warning, because a pond placed against stale heights is not a degraded
pond — it is a pond that does not exist. It happened twice on `skirmish` in one session: both
times the bake was half a unit low, both times the author placed ponds that flooded 101 cells
against the stale data and **zero** against the real terrain.

**Sculpting with the brush desyncs a mesh-authored map by construction**, because the brush
writes `heights` while `terrain_source_mesh` stays as it was. On such a map, re-bake before
placing water (or push the heights back into the mesh with
`tools/terrain/resync_surface_mesh.gd`, which is the same relationship in the other
direction). See
[mesh-baked-terrain.md](mesh-baked-terrain.md) §The bake must SAVE for the other half of this:
a bake that never reached disk is how the drift opens up in the first place.

## A pond shallower than the terrain's relief is drawn and still cannot be seen

**The water plane is flat; the ground under it is not.** A body only 0.2 deep on terrain that
steps in 0.15 increments is geometrically below the steps around it, and from the game's
oblique camera those steps hide the plane completely. Measured on `skirmish`: from directly
above, the pond covered ~7,800 pixels; from the RTS camera angle it changed **zero** pixels,
because every sightline to the water passed through a higher cell first.

This is not a rendering bug and there is nothing to fix in the shader — it is what a shallow
puddle in rough ground actually looks like. It is a hazard of the authoring gesture: **the
level is the height of the point under the cursor**, so clicking near a pond's floor produces
a body a few centimetres deep, which reads as "the water is not visible in game".

`WaterSurfaceMesh` therefore lifts each quad to clear its OWN cell —
`max(level, highest corner of that cell + GROUND_CLEARANCE)`. Over open water every corner is
below the level, so the surface stays flat at `level` and looks like water; only at the
shallows does it ride up over the ground rather than vanish inside it. **Shade is unaffected**
— it comes from the true depth, so the colour still reports real passability — and `level`
remains the only number gameplay reads.

Lifting per CORNER was not enough: it cleared the shoreline ring and left the interior at the
plain level, so the pond drew as a dashed outline with nothing inside it. A quad has to clear
the cell it covers, not merely the corner it touches.

`WaterBasin` also measures two things the author can act on, and the Water brush shows both:

* `max_depth` — the deepest the body gets. Compare it against the terrain's step size.
* `cells_pierced_by_terrain` — covered cells with a CORNER at or above the level. The
  shoreline ring always pierces, by definition; what matters is the proportion. At half or
  more the brush says **TOO SHALLOW TO SEE**.

To get a body that reads: aim further UP the bank, or sink the basin first.

## Authoring

`terrain_brush`'s **Water** mode. Hover the terrain and the preview shows the body a click
would create — built with the *same* mesh builder the finished body uses, so there is no second
approximation to drift from the first. The toolbar says how many cells it covers, how many are
too deep to walk, and whether it runs out to the play edge.

**The level is the height of the point under the cursor.** That is the whole gesture: to raise
a pond, hover further up its bank. A click makes a `WaterBody` node under the `Map`, as one
undoable action, carrying only the authored values.

A click is refused when the basin holds no water (you are pointing at flat ground, or at the
floor of a bowl at its own height) or when it would overlap a body that already exists — the
map indexes cells to bodies one-to-one, and two bodies claiming a cell is not expressible.

The map generator places ponds too, writing each as a `WaterBody` with the same authored values
(a seed cell and a level), charged by its size — see [map-generation.md](map-generation.md).

---

## What the player is told

`CursorReadout` — a one-line panel that follows the mouse — shows `energy: <amount>` over any
body of water. The surface colour says *charged*; only this says *how much*.

It is a panel the controller positions rather than a Control's `tooltip_text`, because nothing
is being hovered but ground: there is no Control to hang a tooltip off. It is deliberately
content-agnostic, so the next world-hover fact reuses it instead of growing a second floating
label.

**Fogged ground says nothing.** A pond's charge is information about the map, and reading it
through an unexplored shroud is the same leak as seeing the pond itself.

---

## A body re-added to the tree rebinds itself

`_ready` fires once in a node's lifetime, and undo/redo removes a `WaterBody` from the tree and
adds **the same instance** back. Initialization hung off `_ready`, so a body that had been
undone came back with no `_map`: `rebuild()` returned early and every later edit to `level` was
silently ignored while the old surface stayed on screen.

Two guards now. Initialization hangs off `_enter_tree`, which fires on every re-entry; and
`rebuild()` re-resolves its map when it has none, so a property edit is itself enough to
rebind. Pinned by `test_WaterPlacement.gd`, which removes a body, adds it back, and asserts a
later `level` change actually re-floods the basin.

## Deliberately not done

- **No physics, no movement effect.** Units walk through shallow water with no speed change and
  no status effect. The mesh is visual. Revisiting this is a gameplay decision, not a
  technical one.
- **Nothing but an extractor may be built in water**, by virtue of nothing else setting
  `allow_submerged`.
- **A hand-authored pond's charge does not scale with anything.** It is whatever `energy` was
  authored; only a generated pond's charge follows its size.
