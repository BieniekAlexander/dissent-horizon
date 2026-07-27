---
title: Range reveal
type: system-note
---

# Range reveal

*Design note for [Dissent Horizon](../../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

**How far does this go?** — asked of a piece the player is reading, and of an order they are
about to give. Both are answered the same way: a ring on the ground, drawn while they are
asking and gone when they stop.

## The shape drawn is the shape queried

Every reach in this game is already a `CollisionShape3D` the simulation tests against — the
fog samples the vision shape, aggro tests the aggro shape, `Attack` measures the weapon's.
The reveal converts those, through `HighlightShape.from_collision_shape`, and draws nothing
of its own. **A drawn range that was re-derived from a stat would agree with the simulation
most of the time, which is worse than not drawing it**: the case where a player needs to
trust the ring is exactly the case where a re-derivation is wrong.

That is also why the fill is the OUTLINE of the real footprint rather than a circle of the
right radius: a box-shaped vision shape reads as a box.

## What counts as a range is a fact the SCENES already state

`EntityRanges` finds shapes by their `debug_shape_*` group, not by node path. Those groups
already exist — the editor colours each shape from
[`DebugShapeColors`](../../../../scripts/rendering/debug_shape_colors.gd) — so the set of
"shapes worth drawing" is authored once and read twice.

Three things fall out of that and each was worth having:

- **Nesting stops mattering.** A weapon's `AttackRange` lives two levels down under
  `Loadout/MissileLauncher`; a path-based lookup had to know the shape of a loadout, and got
  it wrong for exactly the pieces whose reach matters most.
- **The colours cannot drift.** A designer who knows the amber circle is aggro finds the
  amber circle is aggro in game, because it is one table.
- **A new range needs no code.** Give its shape the group and it is drawn.

**Only REACH is revealed.** Selection shapes, movement bodies, target bodies, footprints and
trigger areas all describe where a piece IS, and a player looking at them learns nothing they
cannot see by looking at the unit. Those groups are deliberately absent from
`EntityRanges.GROUPS`.

The one kind with no shape behind it is `EFFECT`: a status effect's reach is a NUMBER on the
effect (`StatusEffect.effect_radius`) rather than a body, so it is built as a circle at the
host. Nothing shipped sets it yet — every effect today acts on its host alone — and that is
the point: the first effect that projects an aura needs no HUD work.

## One node, recomposed every frame

Two things can ask for rings at once — a hovered info card and an armed ability — and
`RTSController.range_bands()` composes the whole list from its own state on every frame.
`RangeIndicator` then draws exactly that.

**Not each source pushing and clearing its own marks.** Two sources that can each be on or
off is four states to keep straight, and a hover that ended while an ability was armed is
precisely the case that used to leave a ring on screen with nothing to explain it. Clearing
is passing an empty list, so there is no "and now put that other thing away" path to forget.

## Hovering an info card is the gesture

Not a key, and not a toggle. The reveal answers a question the player is already asking with
the pointer: the weapon widget shows what the piece shoots and how far out it picks a fight;
the vision widget shows what it sees and what it detects. That is why those exist as separate
cards rather than one stats blob — a blob has nothing for the pointer to ask.

The same treatment covers a status-effect card, and is meant to cover a passive-ability card
the day one has a range. See [hud-layout](hud-layout.md) §The info rows.

### The weapon card's rings

Hovering a weapon card draws up to three rings: the first weapon's **ground reach** (red,
`Kind.ATTACK`), its **air reach** (sky blue, `Kind.ATTACK_AIR`) and the piece's **aggro**
(amber — the wider of its ground and air aggro). A layer the weapon cannot hit draws no ring.
When the ground and air reach are the same ring, it is drawn ONCE in alternating stretches of
both colours (`RangeIndicator.Band.is_alternating`) — two identical circles would show only
whichever was drawn last. Which layer a shape serves is read off its Weapon by the rule the
Weapon itself uses (`EntityRanges._attack_node`). The air colour is named in `EntityRanges`
rather than read from `DebugShapeColors`, because ground and air reach share one debug group.

Placement rings (a structure being placed) still draw every distinct attack reach in the one
attack colour.

## An armed ability shows what the click would do

Two marks, answering the two questions an aiming player has, and each omitted when it has no
answer:

| Mark | Drawn | Omitted when |
|---|---|---|
| the CASTER's reach | ring around the caster | the reach is not a distance |
| the AREA of what lands | filled circle under the cursor | the ability covers a point |

**No reach ring for a global ability.** `UseSanction` measures no distance at all — a
sanction is cast from wherever its target is legal — so a ring around the caster would assert
a limit that does not exist. The same holds for a reach that is not a distance: the Bombard's
is spotted GROUND, and no ring describes that (`Ability.range_closes_by_moving`).

**Fill means "about to put something here".** An area of effect is washed in; a reach is an
outline. Filling reaches as well would put a translucent disc over half the battlefield every
time a card is hovered.

### Which casters the rings are drawn around

**Exactly the ones that would fire** — `RTSController.armed_ability_casters`, which asks the
same arity the click will (see [control-matrices](control-matrices.md) §Cast arity):

- a **SINGLE** cast draws one ring, around the charged caster nearest the aim point: "whose
  range decides this click" is the honest reading of a pair of guns;
- an **ALL** cast draws one ring per charged caster, because all of them are about to fire.

The preview and the order go through one question by construction, so they cannot come to
disagree — holding `modifier_broaden` over a pair of spotters lights both rings *and* sends
both the order.

> **TODO — several rings is a guess at what reads well.** Alex asked to see all of them for
> now and expects to reconsider. Three or four overlapping circles in one colour may be
> soup; the alternatives if so are drawing only their union, or drawing the nearest caster's
> solid and the rest faint.

Tests: `tests/test_RangeDisplay.gd`.
