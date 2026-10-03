---
title: Projectile evasion — how a target makes a shot miss
type: system-note
---

# Projectile evasion

*Design note for [Dissent Horizon](../../../CLAUDE.md). Rules here are authoritative; CLAUDE.md
carries only the pointer.*

> **TODO — definitions first.** The vocabulary below is meant to be stable; the rules built on it
> are mostly undeveloped. Every open decision is a `TODO` under §Open questions, indexed as
> [deferred](../../deferred.md) 1.66.

How a target in the path of a projectile makes it miss, and the terms a design claim about that
is written in. The mechanics the terms describe live elsewhere: an emission's motion, stages,
steering, lead, bleed and lock are [projectiles](projectiles.md) (§Phases, §Turn bleed and lead,
§Losing the lock, §A rocket aims at the hitbox), the speed classes are
[movement/speed_classes](../../movement/speed_classes.md), and what an evasive option is worth as
a skill surface is [design-framework/elasticity](../../design-framework/elasticity.md).

---

## What is measured: hit rate, never kills

**A projectile is judged by the fraction of the shots fired at a target that hit it**
(Alex, 2026-10-03). Whether the shooter KILLS its target is its damage rate, a different question
and out of scope here: a cheap shooter is not meant to kill a target alone before the target
escapes. Several shooters are meant to do that together, and a shot that misses is valuable to
the target's side because it opens a window for OTHER units to kill the shooter.

The instrument is the `hit_rate` simulation check
([simulation-tests](../scenario-scripting/simulation-tests.md) §Counting shots): of the
emissions a group fired that have settled, the fraction that landed on the target group.

---

## The engagement frame

Every term is measured for ONE shot, from its launch to the moment it strikes or ends.

| Term | Definition |
|---|---|
| **Shooter, target, emission** | the piece that fired, the piece it was fired at (`Payload.target`), and the projectile itself |
| **Launch** | the tick the emission is put into play (`Emitter.launch`). Every time below is counted from it |
| **Engagement distance `d`** | shooter to target at launch, horizontally |
| **Aim point** | where a steered emission aims at its target: the centre of the target's hitbox (`Entity.aim_point`) |
| **Line of sight (LOS)** | the line from the emission to the aim point. It rotates as either moves |
| **Hit volume** | what the emission must reach for the shot to count: the target's hitbox, plus the blast radius for a blast emission, measured at the contact's tick ([projectiles](projectiles.md) §The blast is measured at the contact) |
| **Flight time `T_f`** | launch to contact. Depends on `d`, the target's motion and the emission's whole speed profile, not on its top speed alone |

### The target's motion, relative to the line of sight

The target's velocity `v` splits into a component ALONG the LOS and one ACROSS it.

| Term | Definition |
|---|---|
| **Closing** | moving toward the shooter: the along-LOS component points at it |
| **Opening** | moving away: the along-LOS component points away. A target opening at full speed is **fleeing** |
| **Crossing** | the across-LOS component dominates |
| **Aspect** | the angle between `v` and the LOS: 0° fleeing, 90° crossing, 180° closing |
| **Line-of-sight rate** | how fast the LOS rotates, about `v_across / range`. **It grows as range shrinks**, which is why the same crossing target is easy to track far away and hard up close |

### What the target does after the launch

| Term | Definition |
|---|---|
| **Holding course** | keeps its velocity from launch to contact |
| **Reroute** | any change of velocity after the launch |
| **Juke** | a reroute timed to a shot: made a **reaction delay `τ`** after that shot's launch |
| **Jink** | reroutes made on a schedule of their own, regardless of the shots |
| **Reversal** | a reroute that turns the across-LOS component around. Its cost is the turn: a vehicle turning at `ω_t` needs about `π / ω_t` to reverse, keeping speed if it rolls through the turn (`vehicle_light`), stopping first if it pivots (`foot`) |
| **Back-off** | how a HOVERING piece reverses: it backs away at `reverse_speed_ratio` of its speed without turning ([movement](../../movement/movement.md)). It reverses at once, but slowly |

---

## The emission, in the same frame

| Term | Definition | Knobs |
|---|---|---|
| **Speed profile** | launch speed, acceleration, top speed, burn and coast. The AVERAGE speed over the flight, not the top speed, sets `T_f` | `launch_speed_ratio`, `acceleration`, `speed`, `burn`, `coast_speed` |
| **Turning circle `R`** | `s / ω` at speed `s` and turn rate `ω`: the tightest curve it can fly. Bleed shrinks `s` in a hard turn, and so `R` with it | `turn_rate`, `turn_bleed` |
| **Guidance law** | what a stage steers at. **Unguided**: nothing. **Pursuit**: the aim point, live. **Lead**: the predicted intercept, fixed when the stage begins | `turn_rate`, `lead` |
| **Prediction** | a leading stage's aim point: where the target would be at intercept if it held course from that moment |
| **Prediction error `e`** | how far the target actually is from the prediction when the emission gets there. Zero for a target holding course; a juke's whole purpose is to make it large |
| **Correction capacity** | how much of `e` the rest of the flight can still close: bounded by the time left, the turning circle, bleed and the lock. A later pursuit stage is correction capacity, which is how the Warlord's Chase stage undoes a juke |
| **Endurance** | how long and how far the emission can keep flying under power before it expires or falls | lifespans, `burn`, `lock_range`, `lock_cone` |
| **Lock** | whether a steered stage still steers at its target. Lost past `lock_cone` or `lock_range`, after which the emission falls ([projectiles](projectiles.md) §Losing the lock) | `lock_cone`, `lock_range` |

A **hitscan** shot has no path to evade: its payload lands on the target wherever it flew
([projectiles](projectiles.md) §`hitscan` is the aiming rule). **Everything in this note is about
free flight.**

---

## The evasion modes

Each mode is a way for a shot's contact never to happen. They combine in one engagement, but a
design claim should name the mode it means, because each is tuned by different knobs.

### Outpace: run away from it

The target opens faster than the emission closes, until the emission's endurance runs out.

- **Condition:** the emission must cover `d` plus the distance the target opens, `d + v_open · T`,
  before its endurance ends. It never can when `v_open` is at least its sustained speed.
- **Tuned by:** the emission's sustained speed (top speed after burn and bleed) and its
  endurance. A short, powered range that then falls separates fleeing from crossing by DISTANCE;
  a slow top speed separates them by SPEED.
- **Shown in the arena (2026-10-03):** at FLEET (8.5), a fleeing SWIFT Raven (9.3) is hit by none
  of the Warlord's rockets and a crossing one by all of them; a fleeing QUICK truck (4) is hit by
  all. **One top speed cannot separate a fast vehicle from a fast aircraft that both flee and
  cross**, which is why separating by range is the open question below.

### Outturn: get inside the turning circle

Up close, the line-of-sight rate can exceed what the emission can turn to follow, and it
overshoots.

- **Condition:** roughly, the target's line-of-sight rate, `v_across / range`, beats the
  emission's turn rate while the range is about the turning circle `R` or less.
- **Tuned by:** `turn_rate` and the speed (through `R`), and `turn_bleed`.
- **Shown in the arena:** with the Warlord's rocket at 8.5 and 90°/s (`R` about 5.4), a Raven
  merely crossing at 5 units was hit by half the rockets, against 15 of 16 at 8 units. **This is
  a close-range window, and it belongs to the turning circle, not to any juke.**

### Outguess: juke the prediction

A reroute after the launch leaves a leading emission flying at an empty point.

- **Condition:** the prediction error at contact exceeds the hit volume plus the correction
  capacity left. For a reversal with delay `τ`, the error grows with the time left after the
  reversal completes, about `v · (T_f − τ − π/ω_t)`: it needs a long flight, a short delay and a
  quick reversal.
- **Tuned by:** on the emission, `T_f` (speed profile and distance), whether a later stage
  corrects (a pursuit stage, its turn rate, `lock_cone`); on the target, its speed, reversal time
  and the player's reaction delay.
- **Shown in the arena:** at 8 units the Warlord's rocket arrives in about 0.8 s. A truck that
  reverses 0.4 s after launch is still mid-turn, close to the prediction, and the Chase stage
  corrects the rest: **every rocket hit, at every lock cone tried.** At 3 units a reversal 0.2 s
  after launch made about one rocket in six miss.

### Outlast and break lock

The emission stops flying at the target before it arrives: its lifespan ends, or it loses its
lock (past `lock_range`, or off its nose past `lock_cone`) and falls. Outpacing usually ends this
way. Breaking a lock on purpose by turning hard is outturning seen from the lock's side.

---

## Evasion as an elastic option

Evasion is a target's mechanical option in the sense of
[elasticity](../../design-framework/elasticity.md): a **floor**, the hit rate a target suffers with
no attention (holding course, or a scripted reaction), and a **band**, how far a skilled player's
juke or flight lowers it.

- **The floor is set by the emission:** lead makes holding course fatal, which is the point of
  lead.
- **The band is set by the target's mobility and by the window the emission leaves open:** flight
  time, turning circle, correction capacity and endurance.
- **The price is the reaction delay.** A juke must come after the launch and soon after it, so
  it needs the launch to be READABLE (a slow ignition is one tell, [projectiles](projectiles.md)
  §A slow ignition).

A miss is worth most when it buys time for something else: the target's own side gets a window
to kill the shooter. That is the payoff the band should be sized for.

---

## Open questions

- **TODO — the evasion envelope per class pair.** For each emission against each movement class,
  at what distance, aspect and reaction delay does each mode start to work? This should be a table
  measured in the arena, not reasoned out on paper: the paper model
  (`tools/projectiles/rocket_escape_model.py`) has no hitbox size, no jitter, no 3D, and no
  back-off, and it disagreed with the arena on every jinking case.
- **TODO — separating outpacing by range rather than speed.** A powered range that runs out and
  then falls, so a fast vehicle and a fast aircraft both outpace by distance. Alex is revisiting
  which knobs define it ([projectiles](projectiles.md) §Rocket calibration).
- **TODO — the close-range window as a claim.** "Some shots miss at close range, opening a window
  for other units" (Alex, 2026-10-03) is wanted. It is the outturn mode, and its size is the
  turning circle against the close-range line-of-sight rate. Not yet a spec, and not yet tuned.
- **TODO — whether outguessing is a band at all at mid range.** At 8 units no juke helped. Either
  mid-range jukes are not a skill surface (lead plus a correcting stage are simply right), or the
  correction capacity after a prediction must be limited (no pursuit stage, or a tight
  `lock_cone`) for a band to exist.
- **TODO — how a hover piece evades.** Back-off reverses instantly but slowly, so a hover's juke
  makes it a slower target. Alex: hover movement is downstream of "room to outpace projectiles",
  and will follow from it.
- **TODO — readability of the launch.** A juke's price is reaction time, which presumes the
  player can see the shot leave: launch tells, sound, and how they read at game zoom.
- **TODO — does the AI juke?** Units never evade on their own today; an evasion band is only
  ever reached by a player's orders. Whether bots should use it, or units should evade
  automatically at some floor, is open.
- **Related:** [deferred](../../deferred.md) 1.9 (how much projectile lead error is too much).
