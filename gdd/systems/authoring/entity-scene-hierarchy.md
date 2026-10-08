---
title: Entity scene hierarchy
type: system-note
---

# Entity scene hierarchy

*Design note for [Dissent Horizon](../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

**No entity scene inherits another.** A piece's scene is COMPOSED: a root of the class its doc
derives, and one child per component — an instance of a component-library scene for a
component with children or authored defaults, an inline script node for a plain one. Which
components a piece gets is the doc's to say; the derivation is `tools/spec_import/composition.gd`,
and the plan that got here is [composition-rework](composition-rework.md) §Step 4.

## What a piece is entitled to assume

Three tiers, and the point of naming them is that **each answers a different question for a
reader of the code**:

| Tier | Rule | What it licenses |
|---|---|---|
| **Guaranteed** | the composition always creates it for a piece of this shape | `$Node` directly, no null check |
| **Optional** | created iff the doc names its key | `get_node_or_null`, every caller gates on null |
| **Identity** | belongs to one piece (or a named handful) and states what that piece is | resolved by the code that owns the mechanic, never generically |

**A tier is a property of the piece's SHAPE, not of the component.** The shapes are
`SpecComposition.Tier` — an Actor (takes orders or can be damaged), a feature (an uncommandable
fixture), a bodiless piece — crossed with whether it moves and whether it claims cells.
The navigated `Locomotion` (a `Movement`) and what surrounds it (nav agent, movement body,
avoidance obstacle, altitude readout) are guaranteed for a mobile piece and absent from a
structure; an emission's `Locomotion` is a `PhasedLocomotion` instead. `VisionRange` and
`MeshVisual` are guaranteed unless the doc switches them off (`senses.vision` emptied, the
`has_mesh_visual` waiver), and then removed rather than emptied. `Orders`, the order-taking
half, is guaranteed to an Actor unless its doc says `commandable: false`. `Aerial` and `Docking` exist
exactly when the doc says `aerial:` / `docking: true`, straight after `Locomotion`. `Loadout` is
optional for everything.

**A renamed component keeps its scenes.** `SpecComposition.RENAMED_COMPONENTS` maps a
component's former node names to its current one, and the sync renames the node in place —
composing the new name beside the old would put two copies of the component on the piece.

[get-node-or-null-audit](get-node-or-null-audit.md) holds the per-site verdicts, derived against
these tiers.

## The component library

`scenes/components/` holds one scene per component that carries more than a script: children
(`Hurtbox`, `Selectable`, `HPBar`), a shape or texture (`MovementBody`, `VisionRange`, the
indicators), or tuned defaults (`NavigationAgent`). A piece instances it and writes over only
what it does differently.

**The component scene's defaults are the one copy.** Change a default there and every piece
that has not overridden it follows. The HP bar and the selection shape ship CLEARED there for the
same reason commandable.tscn once did — see [generated-visual-defaults](../ux/ui/generated-visual-defaults.md).

**Overriding a node INSIDE a component instance needs the instance marked editable** —
`[editable path="Selectable"]` in the piece's file. Godot loads the override without it, but the
editor drops it on the next save. `TscnDoc.ensure_editable` writes the line whenever the importer
creates such an override.

**A node inside a component instance cannot be removed by the piece**, which is the one place the
old inheritance trap survives. Keep component scenes small enough that nothing inside them is
ever optional.

## Verify by diffing INSTANTIATED layouts, never by reading

`tools/scene_layout_dump.tscn` dumps every entity scene's resolved node tree; with `deep` it
records every stored property, embedded resources expanded. Diff a dump taken before a
structural change against one taken after, and account for every line. That is how the
composition migration was accepted: across 4,213 nodes the only differences were the ones
intended.

## REJECTED — base scenes per kind

`commandable.tscn`, `unit.tscn` and `abstract_structure.tscn` supplied the guaranteed tier by
inheritance until 2026-09-25. Godot cannot remove an inherited node, so every structure carried
locomotion it could not use; a piece that wanted less than its base had to refuse to inherit at
all (the extraction site, the shelter and the Recon Drone did); and a second declaration of an
inherited node leaked and segfaulted at teardown. Composition removes all three.
