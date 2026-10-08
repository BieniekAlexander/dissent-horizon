---
title: Generated visual defaults
type: system-note
---

# Generated visual defaults

*Design note for [Dissent Horizon](../../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

Three things about a piece are consequences of its art rather than decisions in its spec:
whether it can be seen at all, how big its click target is, and where its HP bar sits. None
of them can be authored in a gdd doc — the numbers come from a mesh — and none of them was
governed by anything, which is how the roster arrived at **75 of 79 pieces with an HP bar
anchored below the top of their own model** (a damaged barracks and a damaged Matilda drew
no bar at all, having buried it inside themselves), **12 units with no visible mesh**, and a
selection radius of `0.5` on nearly every unit whatever its size — 0.33x the width of the
Colonial airfield, 3.25x the width of an Anarchist builder.

A fourth pass in the spec importer now derives all three and bakes them into the scene, and
since 2026-10-06 a fourth: the HURTBOX, below.

## What it is not

**Not a calibration rule.** [`spec_rules.gd`](../../authoring/calibration-rules.md) compares
numbers the doc AUTHORED against each other, and all three of its verdicts rest on that: an
`exceptions:` entry is a claim that the author looked at two values they typed and meant the
departure. A mesh AABB is nobody's claim — it is whatever the model exporter produced. So
`EXCEPTIONAL` has no intent to record, `UNACCEPTED` is unactionable in the doc that would
carry the waiver, and `STALE` actively rots: re-export a model 20% larger and every
declaration silently becomes false, with no doc edit anywhere to catch it.

**Not a doc key**, for the same reason. The source of truth here is the art.

## The eight classes

A piece takes the placeholder of its class, and the class is derived, never authored:

| Class | Decided by | Primitive |
|---|---|---|
| bio unit | `Defense.frame_type == BIO` | capsule |
| mech unit | `Defense.frame_type == MECH` | box |
| aerial unit | it has `aerial:` (`FLYING`/`HOVERING`) | wedge |
| structure | has a `Fixture` component | box, sized to the authored footprint |
| ballistic / linear / lofted / homing projectile | the first phase's motion (gravity, pitch, turn rate) | sphere / tracer / bomb / dart |

**Aerial beats frame, and structure beats both.** What a placeholder has to say first is
"this thing flies"; a building has no frame worth drawing.

**A placeholder is deliberately crude and deliberately untinted.** It reads as the wrong
order of thing next to finished art, which is the point — making it nicer would make it
likelier to survive into the build. It carries no material, so it takes no team colour: a
placeholder unit does not tell you whose it is, and that is a cost accepted in exchange for
being unmistakable.

## Baked, not derived at runtime

The three values are written INTO the `.tscn`. The runtime alternative exists and is
already in use for the floating badges (`MeshVisual.model_top_offset`), so the choice owes a
reason: a baked value is visible in the inspector, diffable in review, and adjustable by
dragging the node, which is how the art side of this project actually works.

**The cost, accepted: a re-exported model does not move its own HP bar.** It stays wrong
until somebody clears the value.

## Clearing is the only rebake signal

**The importer never overwrites a value that is already there.** Once a scene carries an HP
bar transform, that transform is the author's, whether they typed it or accepted a generated
one. Rebaking happens only after a developer CLEARS the slot.

The alternative — rebake whenever the stamp still matches, on the theory that an untouched
default is nobody's opinion — silently moves art in scenes nobody opened, on the run AFTER
the model changed, so the diff lands in an unrelated commit. An explicit clear costs one
deliberate gesture and makes every generated write traceable to somebody asking for it.

What "cleared" means differs by slot, because "empty" does:

| Slot | Cleared state |
|---|---|
| HP bar transform | absent, or an origin of exactly `Vector3.ZERO` |
| Selection shape | absent, or a null `shape` |
| Hurtbox | a null `shape` on `Hurtbox/HurtboxShape` — and ONLY that: `--rebake-visuals` never replaces an existing hurtbox shape |
| Placeholder mesh | the node is absent |

**A state filled by art of another kind is not empty.** An emission drawn in flight by a
`Tracer` beam wants no in-flight stand-in, and one whose `PostImpactParticles` holds a particle
system that draws something wants no post-impact one. An empty particles node left over from an
old template draws nothing, and does not suppress the bake.

`Vector3.ZERO` is usable as a sentinel precisely because it is inside the model on every
piece in the game — it can never be a value somebody meant.

**This is why the component scenes' own defaults are cleared.** `scenes/components/hp_bar.tscn`
and `selectable.tscn` ship an HP bar transform with a zero origin and a selection shape with no
shape, so a piece that has not overridden them reads as "nobody has decided this" and gets a
bake. A real value put back on the component would make every piece read as hand-authored, and
the pass would never write anything again.

## The one-off migration

The roster was authored before this pass existed, so ~68 slots held hand-placed values that
the rule above would never have touched — the very values the pass was built to fix. That is
what `--rebake-visuals` is for:

```
godot --headless -s res://tools/spec_import/import.gd -- --rebake-visuals
```

It regenerates every slot the importer does NOT own — an UNSTAMPED value is by definition one
that predates the pass. **A slot the importer has baked, and a human has edited since, is
left alone even under the flag**: that edit is a decision made against this system, and
undoing it is not a migration. So the flag is safe to re-run and converges — a second run
changes nothing.

It is not part of a routine import, and the standing rule is unchanged: clearing a slot is
what normally asks for a fresh bake.

**What it cannot reach: scenes no gdd doc registers.** The importer only opens scenes the
docs point at, so an orphan scene keeps its old values however often the flag runs. Five did
— `petrel.tscn` (whose id `cl_aircraftLight_antiLight` belongs to `clipper.tscn`),
`an_stockpile.tscn`, `hangar.tscn`, `dwelling.tscn`, `tc_infrastructure.tscn`. Those want a doc or a
deletion, and the report keeps listing them until they get one.

## The placeholder lives in the piece's OWN scene

Replacing a placeholder with real art should be a delete and an add, never a
`visible = false` beside it — so the stand-in is a node in the piece's scene, not in anything
shared. That is why it is generated per scene on the rule below. Structures that use the dummy
AS their art instance it themselves, with their own transform.

REJECTED — a stand-in on a shared base. `abstract_structure.tscn` once carried a `Model`
instancing `dummy_structure.blend`, and every structure was stuck with a dummy it could only
hide; adding a generated node to a base instead segfaulted at teardown wherever a piece
declared one of its own. Piece scenes no longer inherit anything
([authoring/entity-scene-hierarchy](../../authoring/entity-scene-hierarchy.md)).

## A placeholder is wanted when `MeshVisual` has no CHILDREN

Not when nothing MEASURES visible. The node is the better question: a `MeshVisual` with
anything under it has had its model supplied, even if that model is currently hidden behind a
shader state or kept as a variant — and the importer's job is to fill an empty slot rather
than to second-guess a full one. The measurement stays as the fallback for a piece with no
`MeshVisual` at all (a projectile).

## The stamps, and the three states

Each generated value carries `metadata/_visual_default_*` recording what was written.
**Ownership is not decided by the stamp** — a baked value is left alone either way. The
stamp is what lets the report distinguish:

- **generated** — baked, and untouched since.
- **tuned** — baked, and a human has since changed it. Working as intended.
- **authored** — never the importer's. It will never be regenerated; clearing it is the ask.

## The hurtbox

Decided 2026-10-06. **A piece's hurtbox is fitted to its model and stands ON its origin**, which
is its base: navigation places a piece by its origin, so the body lies above it. The hurtbox is
what a shot strikes, where a steered weapon aims (its centre), and what EVERY piece-to-piece
range is measured from (`Entity.hull`), so all three follow the model.

| Piece | Shape | Fitted to |
|---|---|---|
| fixture (a structure, or a feature with a `footprint:`) | cuboid | the authored footprint × the model's height |
| MECH unit | cuboid | the model's extent; it turns with the piece |
| BIO unit, aircraft | upright cylinder | half the model's wider side; the model's height |

From the origin, or the model's lowest point if that is higher, to the model's top, with a small
floor so a sliver stays hittable. Cylinders and cuboids only: they are what `Hull` measures, and
a shape the player cannot predict from the model is worse than a slightly loose one.

- **A MECH unit's reach varies with its facing**, accepted: a box measured edge to edge reaches
  further along its length. Range stays SYMMETRIC either way — `Hull.gap` is the same both
  ways for any pair of shapes, so whatever reaches you, you reach back at the same gap.
- **Ranges follow the hurtbox, not a separate range shape** (Alex, 2026-10-06). REJECTED — a
  distinct attack-range shape: two shapes that can drift, so a shot could land on what range
  calls out of reach.
- **Structures are measured from their walls.** Before this every structure's hurtbox was the
  component's 0.5-radius column at its centre, so attacking a building meant closing on that
  column; attackers now engage from their real reach.
- **It is not a doc key.** `body.hurtbox` is retired: the art is the source of truth, and the
  importer refuses the key.
- **Superseded:** the game copied the movement body over every hurtbox at load and raised it onto
  the base. The authored hurtbox was overwritten, and the editor showed shapes centred on the feet.

TODO: the movement body (`MovementBody`) is still a cylinder centred on the origin, half
underground. It only collides with other bodies for avoidance, so nothing aims at it — see
`gdd/tasks.md` T-093.

## What stays hand-authored

- **Art direction of every kind.** The pass supplies geometry, never a material, a texture
  or a model.
- **A projectile's post-impact visual, unless it is EARNED.** Generated only where the
  projectile persists past the hit (a later phase lasting more than a tick) or carries a blast, because
  a bullet that vanishes on contact wanting no impact puff is a legitimate authoring choice
  and not a gap. The burst is a sphere for every motion rather than the motion's own
  mesh: a burst shaped like the shell that caused it tells the player nothing happened.
- **The selection shape of any piece that has one.** Only trivial primitives are ever
  generated — a cylinder for units, a box for structures. A convex hull would fit better and
  is deliberately not used: selection is a CLICK TARGET, not a silhouette, and a shape the
  player cannot predict by looking is worse than one that is slightly too generous.

## The numbers, and why

- **Selection radius floors at `MIN_CLICK_RADIUS`** rather than fitting the mesh. The
  roster's infantry are 0.31–0.48 world units wide, and a click target that honest makes
  them fiddly to click and nearly impossible to drag-select. The overhang on small models is
  the accepted cost.
- **Structures take their selection box from the authored grid footprint, not the mesh** — a
  roof or a radar dish that overhangs the footprint must not become clickable ground.
- **HP bar width is two thirds of the model's wider horizontal extent**, floored at
  `HP_BAR_MIN_WIDTH`. At 1.0 the bar becomes a second silhouette, and on infantry a wider one
  than the unit itself, which is exactly what the old fixed 0.43 did.
- **The bar clears the model top by `HP_BAR_CLEARANCE`** rather than sitting at it, so it
  cannot z-fight the highest polygon.

## Where it lives

| File | Role |
|---|---|
| `tools/spec_import/visual_defaults.gd` | pure rules — takes numbers, returns descriptors, touches no Node |
| `tools/spec_import/visual_measure.gd` | reads a scene: model extents, which slots are empty |
| `tools/spec_import/scene_sync.gd` | the writer (`_sync_piece_visuals`, `_sync_projectile_visuals`) |
| `tools/ui_audit.gd` | the report |
| `tools/visual_defaults_preview.gd` | render harness — no assertion can see a buried bar |
| `tests/test_VisualDefaults.gd` | the arithmetic and the classification |

The importer and the report share the measuring and the rules, so "this piece has no
visual" means the same thing in the thing that fixes it and the thing that lists it.
