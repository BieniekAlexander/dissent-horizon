---
title: Movement classes
# NOT YET A SPEC: no `kind:`, so the importer skips this doc. It holds the movement
# classes; a unit doc still authors its own `movement:`.
#
# Movement classes. PROPOSED 2026-09-26, not yet adopted: nothing reads this block, and no
# unit doc names a class yet. `speed` names a class from speed_classes.md. turn_rate is
# degrees/s; acceleration and deceleration are world units/s^2 (deceleration a signed
# floor, so negative). min_turn_speed_ratio is GROUNDED only; reverse_speed_ratio is
# HOVERING only. Why each value: the body of this doc.
classes:
  # Foot (GROUNDED). Pivots in place, stops dead; no acceleration limit. Infantry, and
  # the small ground drones, which move like infantry although they are MECH.
  foot:            {mode: GROUNDED, speed: SLOW,     turn_rate: 1080, min_turn_speed_ratio: 0}
  foot_laden:      {mode: GROUNDED, speed: SLUGGISH, turn_rate: 1080, min_turn_speed_ratio: 0}
  # Vehicles (GROUNDED). Brakes beat engines; every one keeps rolling while it turns.
  vehicle_heavy:   {mode: GROUNDED, speed: STEADY, turn_rate: 90,  max_acceleration: 0.75, max_deceleration: -2.25, min_turn_speed_ratio: 0.3}
  vehicle_line:    {mode: GROUNDED, speed: BRISK,  turn_rate: 150, max_acceleration: 1.5,  max_deceleration: -4.5,  min_turn_speed_ratio: 0.5}
  vehicle_light:   {mode: GROUNDED, speed: QUICK,  turn_rate: 180, max_acceleration: 3.0,  max_deceleration: -6.0,  min_turn_speed_ratio: 1.0}
  # Hover (HOVERING). Can stop and hold a point; backs off at reverse_speed_ratio.
  hover_heavy:     {mode: HOVERING, speed: BRISK, turn_rate: 90,  max_acceleration: 1.0, max_deceleration: -1.5, reverse_speed_ratio: 0.2}
  hover_medium:    {mode: HOVERING, speed: QUICK, turn_rate: 180, max_acceleration: 2.0, max_deceleration: -3.0, reverse_speed_ratio: 0.35}
  hover_light:     {mode: HOVERING, speed: FAST,  turn_rate: 270, max_acceleration: 4.0, max_deceleration: -5.0, reverse_speed_ratio: 0.6}
  # Flyers (FLYING). Never stop; thrust outpaces braking, so deceleration is the weaker.
  flyer_heavy:     {mode: FLYING, speed: QUICK,   turn_rate: 60, max_acceleration: 1.0, max_deceleration: -0.5}
  flyer_medium:    {mode: FLYING, speed: FAST,    turn_rate: 90, max_acceleration: 2.0, max_deceleration: -1.0}
  flyer_light:     {mode: FLYING, speed: BLAZING, turn_rate: 60, max_acceleration: 3.0, max_deceleration: -1.5}
---
# Movement classes

The movement classes, built on the speed ladder in [speed_classes](speed_classes.md). What
each class means in a fight is in
[design-framework/commitment-and-movement](../design-framework/commitment-and-movement.md)
§Movement classes; the class values live only here, in the frontmatter above.

## How the values were chosen

Every class is placed with the disengagement tax in view
([commitment-and-movement](../design-framework/commitment-and-movement.md) §The disengagement
tax): the time to get moving away from a fight is `T_out = θ/ω + v/a`, and a unit slower than
its pursuer (`Δv ≤ 0`) cannot leave at all. The class decides `T_out`; the speed tier decides
which side of the `Δv` cliff it sits on against each other class.

- **Foot** stops and turns for free (`T_out` is a fraction of a second), and is slower than
  every vehicle and aircraft. It commits cheaply and cannot leave: its whole disengagement
  question is the `Δv` cliff. `foot_laden` exists so the slow roles (builders, the Vanguard,
  neutral inhabitants) can be caught by ordinary infantry.
- **Vehicles** all have finite acceleration, brakes about three times their engine (twice for
  the light and drone classes, which are nimble anyway), and a non-zero turn-speed ratio, so
  none pivots like a soldier. Commitment falls as speed rises: `vehicle_heavy` pays roughly
  five seconds to turn and get going (the line-to-siege band), `vehicle_line` about three,
  `vehicle_light` about two. Fast units turn slowly relative to their speed, so their turning
  circle stays around a unit or more and a fast vehicle has to be aimed. The small ground
  drones are MECH but move as `foot`: they are the infantry of an army with no soldiers.
- **Hover** can stop and hold a point, and backs away at `reverse_speed_ratio` without turning
  first. That ratio is its kiting lever: `hover_heavy` barely backs off (a stable platform that
  commits), `hover_light` backs off at most of its speed (it kites). Hover sits one tier above
  the vehicle of the same weight, so aircraft are marginally faster than ground units.
- **Flyers** never stop, so their turning circle `v/ω` is always real and must fit inside
  their reach (the importer's `turn_radius_within_reach` rule). Their deceleration is the
  weaker of the pair: thrust gets an aircraft moving and little sheds that speed again, so it
  overshoots and attacks in passes. `flyer_light` is the BLAZING tier: fast enough to outrun
  standard projectiles, with a turning circle wide enough that it cannot dogfight.

## Proposed assignments

| class | units |
|---|---|
| `foot` | Sharpshooter, Sapper, Irregular, Shock Trooper, Warlord, Hijacker, Juggernaut, Recruit, Badger, Sleeper, Constable, Shock Drone, Point Defense Drone |
| `foot_laden` | Technician, Servant, Vanguard, terrestrial |
| `vehicle_heavy` | War Wagon, Avalanche, MLRS |
| `vehicle_line` | Toxin Tractor, Matilda, Sloop, MDC, Refraction Tank, Gatling Tank, Liberator |
| `vehicle_light` | Collective, Stock Truck |
| `hover_heavy` | Reverence, Fabricator, Sentinel |
| `hover_medium` | Caravel, Canary, Clipper, Surveyor, Raven |
| `hover_light` | Harpy |
| `flyer_heavy` | Condor, Purifier, Viper |
| `flyer_medium` | Drake, Interceptor, Kamikaze (turn rate raised; see below) |
| `flyer_light` | Dropship |

The Recon Drone does not move and takes no class. The Technician is a grounded, light BIO
builder (its hovering spec was a testing leftover). The Kamikaze takes `flyer_medium` with one
departure, a faster turn rate: it hits at melee reach, and `turn_radius_within_reach` is a
STRUCTURAL rule that no exception can waive, so its diving turn has to fit the melee circle.
