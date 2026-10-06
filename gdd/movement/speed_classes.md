---
kind: SpeedLibrary
title: Speed classes
# THE SOURCE OF TRUTH for every authored speed. A unit's `movement.speed` and an emission's
# `speed:` (or a phase's `motion.speed`) NAME one of these classes, never a number; the spec
# importer resolves the name to the value here. Retune a class here and re-run the importer,
# and every piece and emission in it moves with it. Why buckets: the body of this doc.
#
# World units per second, slowest first. The importer refuses a ladder that is not strictly
# increasing in the order written; nothing else about the values is enforced.
speeds:
  ZERO: 0
  SLUGGISH: 1.40
  SLOW: 1.65
  STEADY: 2.20
  BRISK: 3
  QUICK: 4
  FAST: 5.25
  RAPID: 7
  FLEET: 8.5
  SWIFT: 9.3
  BLAZING: 12.4
  SCORCHING: 16.5
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

## The one rule: the ladder is monotonic

**The classes are listed slowest first, and each is strictly faster than the one above it.**
The importer refuses a ladder that breaks this (`SpecRegistry._register_speed_library`), so
the order names read in is the order they rank in, and "one class up" always means faster.

Nothing else is a rule:

- **A rung does not belong to a kind of piece.** A rung is a speed, not a category. Most
  vehicles are slower than most aircraft and most projectiles faster than both, but a fast
  vehicle may share a rung with a slow aircraft, and a slow projectile may be outrun by an
  aircraft. Those cases are rare and deliberate, and the ladder allows them.
- **The spacing is not fixed.** The values were initialised at 4/3 steps from SLOW (a pursuer
  one rung up closes at a quarter of its own speed, which is a "can chase it down" margin), and
  are free to move off that grid. SUPERSONIC already does.

## Where the values came from (2026-10-03)

[Zero Hour](zero-hour-speed-reference.md) was the reference, anchored on infantry: its basic
soldier (Speed 20) is SLOW here, so one of its speed units is 0.0825 u/s.

- **Ground** keeps the values it had. Zero Hour runs main battle tanks at infantry speed; this
  game keeps every vehicle a rung or more above infantry, with light vehicles well above that.
- **Aircraft were raised by roughly 2.3–4×** (2026-10-03). Zero Hour's helicopters and jets run
  at 6–9× infantry; ours sat at 2–3×. Each aircraft kept its place relative to the others: the
  old BRISK aircraft are RAPID, QUICK → SWIFT, FAST → BLAZING, and the few that outrun the
  standard rocket are HYPER. Re-runged FLYING pieces had their turn rate scaled by the same
  factor, so each keeps the turning circle its reach, runways and orbits were tuned against;
  every re-runged aircraft had its acceleration and deceleration scaled too, so it reaches
  cruise in the time it did.
- **Projectiles** sit mostly above every unit, as in Zero Hour, where rockets fly at about 11×
  infantry and shells faster. The exceptions are deliberate: a slow, hard-homing rocket that a
  fast vehicle can outlast (the Warlord's), and aircraft fast enough to outrun the standard
  rocket.

**TODO — the projectile side is exploratory (Alex, 2026-10-03).** How projectiles and
evasion should work is still being explored; manoeuvrability (turn rates, acceleration,
interception geometry) is the intended lever for dodging, and is deferred until more
projectiles exist. Speeds today are set so that low-tier projectiles hit most of what they
are fired at.

## Who is on each rung today

Descriptive, not prescriptive: this is what the docs name today, not a rule about what may.

| Class | u/s | Who |
|---|---|---|
| ZERO | 0 | does not move: a stationary piece (the Recon Drone), or an emission that stays where it is placed (planted bombs, the lazer) |
| SLUGGISH | 1.40 | very strong or laden infantry: builders, the Vanguard, terrestrials |
| SLOW | 1.65 | infantry, and the small ground drones (the anchor: Zero Hour 20) |
| STEADY | 2.20 | the slowest vehicles: artillery, heavy transports |
| BRISK | 3 | the middle vehicles |
| QUICK | 4 | the fastest vehicles in play |
| FAST | 5.25 | a fast light vehicle, when there is one; the Warlord's slow homing rocket; bombs and lobs |
| RAPID | 7 | heavy hover aircraft |
| FLEET | 8.5 | the Warlord rocket: fast enough to hit a SWIFT aircraft crossing its front, too slow to catch one flying away (Alex, 2026-10-03; projectiles.md §Rocket calibration) |
| SWIFT | 9.3 | most aircraft, hovering and flying; the Badger rocket's coast |
| BLAZING | 12.4 | fast aircraft (the Drake, the Harpy) |
| SCORCHING | 16.5 | the standard rocket: the SAM, the Badger's boost, aircraft-fired ground missiles. Catches every aircraft below HYPER |
| HYPER | 20 | light, fragile aircraft that outrun the standard rocket (the Interceptor, the Kamikaze drone, the Dropship); fast unguided rockets |
| SUPERSONIC | 28 | bullets and shells, and AA missiles that catch everything. Faster than anything that flies; only the travel time is left |

`hitscan: true` does NOT take an emission off the ladder: it is the aiming rule (the payload
lands on the piece fired at), and the shot still flies at its speed class
([combat/projectiles](../systems/combat/projectiles.md) §`hitscan` is the aiming rule).

`aerial.orbit_speed` names a class too. Other speed-like keys are still numbers: `min_speed`,
`launch_speed_ratio` and the `*_speed_ratio` chassis fractions are not speeds on this ladder.
