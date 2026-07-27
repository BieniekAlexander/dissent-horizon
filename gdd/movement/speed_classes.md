---
kind: SpeedLibrary
title: Speed classes
# THE SOURCE OF TRUTH for every authored speed. A unit's `movement.speed` and an emission's
# `speed:` (or a phase's `motion.speed`) NAME one of these classes, never a number; the spec
# importer resolves the name to the value here. Retune a class here and re-run the importer,
# and every piece and emission in it moves with it. Why buckets: the body of this doc.
#
# World units per second, slowest first.
speeds:
  ZERO: 0
  SLUGGISH: 1.40
  SLOW: 1.65
  STEADY: 2.20
  BRISK: 3
  QUICK: 4
  FAST: 5.25
  RAPID: 7.2
  BLAZING: 15
  HYPER: 20
  SUPERSONIC: 28
---
# Speed classes

**One ladder for units and tokens (emissions) alike**, so "can X outrun Y" is a comparison of
two class names. The values live only in the frontmatter above: docs name a class, and the
spec importer (`kind: SpeedLibrary`, see [tools/spec_import/README.md](../../tools/spec_import/README.md))
resolves it. A number where a class belongs is an import error. The movement classes that
name these tiers are in [movement](movement.md); what speed buys in a fight is
[design-framework/commitment-and-movement](../design-framework/commitment-and-movement.md)
§Movement classes.

## How the values were chosen

The anchors are SLUGGISH and SLOW. **From SLOW to HYPER each tier is 4/3 of the one below**: a
pursuer one tier up closes at a quarter of its own speed, which is the "can chase it down"
margin at every step. That ratio was the starting point, not a rule — the ladder is expected to
depart from it (SUPERSONIC already does).

| Class | Who |
|---|---|
| ZERO | does not move: a stationary piece (the Recon Drone), or an emission that stays where it is placed (planted bombs, the lazer) |
| SLUGGISH | SLOW × 0.85. Very strong pieces held back by mobility; outruns nothing |
| SLOW | `an_bioLight_builder`'s speed. Infantry: numerous, not fast |
| STEADY | the slowest vehicles: faster than infantry, and little else |
| BRISK | the middle vehicles |
| QUICK | the fastest vehicles; below every aircraft |
| FAST | most aircraft (the Drake). A grounded unit here is an exception |
| RAPID | TOKENS: the standard unguided or slow-homing projectile. It catches every unit class below it and none above |
| BLAZING | the fastest units: a few fragile aircraft. They outrun RAPID projectiles; only HYPER and SUPERSONIC ones still catch them |
| HYPER | TOKENS: the projectiles that keep up with BLAZING (fast homing) |
| SUPERSONIC | TOKENS: bullets and shells. Faster than anything that flies; only the travel time is left |

`hitscan: true` does NOT take an emission off the ladder: it is the aiming rule (the payload
lands on the piece fired at), and the shot still flies at its speed class
([combat/projectiles](../systems/combat/projectiles.md) §`hitscan` is the aiming rule).

Other speed-like keys are still numbers: `min_speed`, `launch_speed_ratio`, `orbit_speed` and
the `*_speed_ratio` chassis fractions are not speeds on this ladder.
