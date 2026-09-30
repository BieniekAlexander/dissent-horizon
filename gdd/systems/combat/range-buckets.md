---
title: Range buckets
type: system-note
---

# Range buckets

*Design note for [Dissent Horizon](../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md carries only the pointer.*

**A weapon's reach is one of a few named buckets, never a number of its own** — and so are
vision, detection and area of effect (see below). Each bucket
is an entry of the one shape-library doc, [`gdd/shapes/shapes.md`](../../shapes/shapes.md) — a
named cylinder or sphere — and a weapon's `reach:` names one per target layer
(`ground_range_medium`, or `{ground: ground_range_long, air: air_range_siege}`). The importer
refuses a bare number. Doc and scene mechanics:
[`tools/spec_import/README.md`](../../../tools/spec_import/README.md) §kind: ShapeLibrary.

**This note names buckets and never catalogues their radii.** The radii live only in
[`shapes.md`](../../shapes/shapes.md), where a designer tunes them side by side; a copy here
would go stale the first time one moved. A number in this note is an illustration or a
record of what was true at the time, never the current value.

## Why

Reach was a per-unit balance knob, traded against speed and toughness. With one number per
weapon, retuning one unit's range changed its standing against every other unit's range,
so every change meant revisiting the whole roster. Buckets make range a TIER: moving a unit
to another bucket is a deliberate change of tier, and changing a bucket's radius moves every
weapon in it together, so their range order stays the same.

**Superseded:** `reach: 7.5`, a free per-weapon radius. Every weapon was moved to the
NEAREST bucket (2026-09-24). The exceptions went to siege on purpose: the MLRS, the
Technocratic 15-reach laser and the Colonial AA site.

## The buckets

Ground and air are separate families, because anti-air wants more reach than a ground
weapon of the same role (aircraft close distance faster than infantry can be walked out of
it). Melee has a bucket in each family so a contact weapon stays at or below the melee
threshold. Melee is derived from reach, so moving a rammer's weapon to `short` would take
away its dive.

The radius is the only authored geometry. Every bucket is as tall as every other
doc-governed shape, so altitude and slope never decide whether a target is in reach. The
first spec named a height of 10, which would have put cruising aircraft out of reach of
everything.

## Pitfalls accepted

- **Ties rounded down.** A reach exactly between two buckets went to the lower one (with
  the radii of the time, the four 10-reach ground weapons went to `long`, not `siege`, and
  an 8-reach air weapon to `air_range_long`, not `air_range_siege`). Siege stays reserved
  for pieces whose role IS range.
- **Differentiation lost.** 10 ground weapons now sit in `long`, where they used to span 7–10. Within a bucket, units are now told apart by speed, toughness and vision only.

TODO: `technician.tscn` and `petrel.tscn` have no spec doc, so the importer never touches
them and they keep a cylinder of their own (0.375 and a scene-authored radius). Give them
docs, or point their range nodes at a bucket by hand.

## Aggro is derived from reach

A piece picks fights at a radius its weapons imply. It is never authored: `senses.aggro:` is
refused by the importer. The rule (`RangeShapes.aggro_radius_for_reach`):

- **a fixed margin past reach**, clamped between a floor and a ceiling (`AGGRO_MARGIN`,
  `AGGRO_MIN_RADIUS`, `AGGRO_MAX_RADIUS` in `scripts/entities/range_shapes.gd`);
- **a piece that cannot move is held to its reach.** It cannot walk toward what it latches
  onto, so acquiring past reach would lock it onto targets it can never fire on;
- **one volume per target layer.** `AggroRangeGround` follows the longest ground reach and
  `AggroRangeAir` the longest air reach; the scan runs once per layer against that layer
  only, so a long anti-air reach never pulls a unit toward ground targets. A layer the
  piece cannot hit has no volume. The leash reads the volume for its target's layer;
- **a bunker takes its occupants' reach**, plus its `range_bonus`, recomputed
  whenever its occupants change. A hold that does not fire lends nothing.

The shapes are a runtime library: one shared cylinder per radius, never mutated. They are
derived rather than authored because the bunker case changes at runtime.

**Superseded:** a per-piece `senses.aggro:` radius, with two calibration rules to police it
(`armed_declares_aggro`, `immobile_aggro_within_reach`). Both rules are gone. The
immobile rule now lives inside the formula itself.

## Ranges are measured between hulls

**Every range from one piece to another is the GAP between their footprints**, against the
range's radius: weapon reach, aggro, the attack leash, stealth detection, interaction reach,
the Liberator's reach and the Anarchist aura. A footprint is the piece's target body on the
ground plane, a circle or a box turned about Y (`Hull`, from `Entity.hull`). So "reaches 12"
means 12 between the nearest edges, from whichever end it is asked, and two pieces with the
same reach engage at the same separation however different their bodies.

- **A range to a POINT** — a ground shot, a beacon's coverage, a region's centre — is the gap
  from the footprint to that point: a point is a footprint of no size.
- **A region** (a Defend area) is measured from its centre point, for acquiring and for
  releasing alike.
- **Height plays no part.** The broad-phase shape query keeps each volume's height and layer
  mask, and the footprint gap decides.
- **Vision is not a hull range.** Fog is stamped from the source's centre and a target is seen
  when its centre is clear, so a sense measured against fog cannot be measured between hulls
  without re-stamping fog by footprint.
- **The HUD ring is the reach widened by the piece's own footprint** (`EntityRanges.shape_for`),
  so it shows where a target's edge comes into reach. A box-bodied piece is widened as the
  circle about it, which slightly over-states the reach off its faces.

**Superseded:** three geometries at once. Reach shifted a query toward the target's centre by
the firer's extent along that ray; aggro, detection and interaction reach ran a circle from the
centre against the target's real body; the leash compared centre points. Each favoured the
bigger body, and they disagreed with each other: a garrisoned building was picked up by
attackers slightly farther out than it could pick them up, and its attack order was dropped
by a centre-measured leash at a range its occupants could still fire.

TODO: the `nt_building_*` pieces and `an_infrastructure` keep the component default target body, a
0.5-radius cylinder, rather than one the size of their 4×4 footprint, so every range treats
them as the point at their centre. A footprint-sized body changes how close everything must
come to hit them.

## Asymmetries between the families

The buckets exist so that the families can be ORDERED against each other. The orderings
below are calibration intent: nothing checks them across the shape library, and a
per-unit rule (`reach_within_vision`, `detection_within_vision`) is still checked on
each piece, with declared exceptions.

- **Two artillery classes.** `ground_range_artillery` sits BELOW structure vision
  (`vision_ground_large`): it out-ranges infantry vision but a base sees it coming.
  `ground_range_siege` sits ABOVE structure vision: it shells a base from where the base
  cannot see it. (Swapped 2026-09-26: siege reads as the longer of the two.)
- **Command-centre vision tops every reach.** `vision_ground_huge` stays above every
  attack range, artillery included, so a base's core is never shelled blind.
- **Reach past own vision is per piece, not per class.** An artillery piece may depend
  on spotters (vision below its reach) or spot for itself; not every artillery piece
  must. Aggro is vision-gated
  ([target-acquisition](target-acquisition.md)), which is what makes spotting matter.
- **Detection against stealth vision.** `detection_small` is out-seen by every stealthed
  unit. `detection_medium` is out-seen by SOME stealthed units — those can evade it by
  keeping their distance. `detection_large` out-reaches the vision of EVERY stealthed
  unit, so a dedicated detector cannot be evaded that way.
- **Units that out-see structures are rare.** Some units may see farther than structure
  vision, sparingly; low-vision structures (a vulnerable extractor, for instance) are
  the other side of the same lever.
- **Area of effect is set against body size,** loosely, since how tightly a player bunches
  their units matters more than the radius.

TODO: any Informant-granted stealth can put a HOVERING unit under stealth, so
`detection_large` has to clear `vision_aerial_large`. If that puts it above every vision
bucket a unit can carry, a dedicated detector trips `detection_within_vision` unless it
declares an exception or a vision bucket is added for it.

TODO: the aggro ceiling (`AGGRO_MAX_RADIUS`) sits below both artillery classes — and, since
the radii were retuned, below `ground_range_long` and `air_range_long` too — so a target
between the ceiling and the reach is never picked up idle. It can only be engaged by
an explicit order, or answered by retaliation ([target-acquisition](target-acquisition.md)).
For now that gap is intended: a player who targets by hand gets a little more damage out of a
long-reach piece than one who leaves it to attack commands (2026-09-29). Expect to revisit it.

## Vision, detection and area of effect are buckets too

`senses.vision:`, `senses.detection:` and an emission's `blast:` name library shapes, and a
bare number is refused on each. Vision and detection may still be taken away (`false` /
left empty).

**Vision** is chosen by what the piece is (radii: [shapes.md](../../shapes/shapes.md)):

| bucket | who |
|---|---|
| `vision_ground_small` | infantry (grounded BIO) |
| `vision_ground_medium` | grounded vehicles; structures of four cells or fewer |
| `vision_ground_large` | every other structure, and the Anarchical command centre |
| `vision_ground_huge` | the other command centres |
| `vision_aerial_medium` | FLYING units |
| `vision_aerial_large` | HOVERING units, whatever their frame |

**Detection** has three tiers (decided 2026-09-25):

| bucket | who |
|---|---|
| `detection_small` | pervasive: EVERY BIO unit, plus the Sentinel |
| `detection_medium` | low-investment detection: cheaper, faster, more fragile, lower tech |
| `detection_large` | high-investment dedicated detectors: pricier, slower, tougher, higher tech |

`detection_small` is authored in each doc, not by any rule in code, so a bio unit could
still be written without it. No unit carries `medium` or `large` yet; what is decided is
where they sit (see §Asymmetries between the families).

**Area of effect:** `aoe_tiny`, `aoe_small` and `aoe_medium` are spheres, so a ground impact
never reaches a cruising aircraft. `aoe_large` is a full-height cylinder and hits ground and
air alike. It is the first size to span both, and that line may move.
The blast is always queried UPRIGHT, however the projectile is pitched, so a tall one
cannot be tilted into a line.

**Superseded:** per-piece radii for all three. Vision 5–20 collapsed into six buckets; the
three authored blasts (1.5, 2.0, 3.0 at the time) went to the nearest bucket (`aoe_small`,
`aoe_medium`, `aoe_medium`).

TODO: blasts authored only in scenes (the kamikaze bomb among them) have no doc key, so they
still carry their own sphere.

TODO: `resources/generated/shapes/*.tres` are neither committed nor gitignored. Scenes load
them, so ignoring them (§10 for generated artifacts) would break a fresh checkout until the
importer runs; the sibling `resources/generated/*.json` are committed. Decide which way.
