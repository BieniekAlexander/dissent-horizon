---
title: Unit descriptors — the vocabulary for power-budgeting a roster
type: design-note
---

# Unit descriptors

**A designer's tool, not a player-facing one.** Descriptors exist to budget a unit's power and
to make a roster's shape deliberate: which kinds of unit a faction has, which it has several of
(and must therefore make distinct), and which it lacks (and must therefore compensate for).

Players never see a class. What they see is the general systems — damage, armour, movement —
and they build their own mental models from those, which is part of the fun.

---

## Descriptors are read off properties

A descriptor is a statement about a unit's properties, never a label assigned beside them.

| Descriptor | Grounded in |
|---|---|
| Frame | `Defense.frame_type` — BIO / MECH |
| Armour | `Defense.armour_type` — LIGHT / MEDIUM / STRONG |
| Layer | `aerial.mode` (grounded when absent) — grounded / hovering / flying |
| Durability | hit points with armour: effective health against typical damage |
| Mobility | speed, turn rate, acceleration, crush class |
| Reach | weapon range |
| Output shape | target filter (anti-X), area radius, targets at once |
| Duty cycle | reload time, or a charged clip and a rearm trip |
| Deployment | whether it must deploy to fire, and how long that takes |
| Function | non-combat roles: transport, build, spot, support, capture, dominion, infrastructure |
| Investment | the cost band, below |

**A comparative descriptor is relative to units of similar properties**, not to the whole
roster. A slow BIO unit is generally slower than a slow MECH unit; "slow" means slow for what it
is.

**Only two duty cycles are worth generalising**: a long reload, and a rearm trip. Every other
recharge mechanism is rare enough to be designed per piece.

---

## Power is budgeted by cost band

**Cost is energy, tech depth and production time** — there is no population mechanic. A
structure also costs infrastructure.

A unit may depart from its class on any axis, provided it pays for the departure somewhere and
stays inside its band. **No pairing is off-limits in advance**; a risky design is tried, and
what it taught is logged here as a case study.

---

## Canonical classes, as framing

Drawn from Command & Conquer and StarCraft. These are prose for thinking with; nothing in the
implementation names or tests them.

- **Infantry** — BIO, slow, numerous, cost-effective, fragile.
- **Light vehicles** (trucks) — fast, lightly armoured, strong against infantry, weak against
  armour.
- **Tanks** — MECH, durable, moderate speed, strong output, slow to reposition; cannot chase.
  `cl_mechMedium_antiMech` is one.
- **Artillery** — long reach, slow or deployed, area output. Area denial belongs here too,
  loosely: a sniper that must deploy, outranges nearly everything, and fires on one BIO target
  at a time is artillery by reach and deployment, and departs from it on output shape.
- **Helicopters** — fragile, very mobile, strong firepower.
- **Planes** — very fast, fragile, very effective per run, long rearm cycle.
- **Transports, support, stealth** — defined by function rather than by combat numbers.

**The interesting designs are the deviations**: slow artillery, mobile artillery and air
artillery are one class read along different mobility and duty-cycle values; the Aurora is
artillery that bought speed with a long rearm; the rocket buggy bought speed with the attention
its multi-targeting costs ([elasticity](elasticity.md)). A class is a common cluster of
descriptor values, and a design earns its place by where it leaves the cluster and what it pays.

---

## Rules of thumb

Correlations, not constraints — each is broken on purpose when a design calls for it.

- **Air units are never BIO**, and are rarely cheap or low-tech. A durable flier pays in tech
  requirement, speed and situational specificity.
- **BIO is cheaper**, and has less health and speed than MECH.
- **Flying units dock to reload.** Some grounded units will as well.
- **MECH has a medium or high crush class.**

A rule of thumb is downstream of properties. Elasticity is investigated on the properties
directly, not on the descriptor they happen to cluster into.

---

## Factions depart systematically

A faction's identity is a direction it leaves the norms in — declared, with its compensation, in
[matchups](matchups.md) §Identity departures.

---

## Piece ids state descriptors, and may drift

An id (`<faction>_<frame><Armour>_<role>`) names a piece by its descriptors. Nothing keeps that
name true: a piece retuned out of its armour class keeps the old id. **The drift is accepted** —
the roster is under constant revision, and an id is revisited when it is noticed to be wrong
rather than enforced. [composition-rework](../systems/authoring/composition-rework.md) records the
same fact from the implementation side.

---

## Rejected as classes

- REJECTED — **momentum** (output scaling with speed at the moment of attack): units reach top
  speed in a fraction of a second, so speed barely varies. The Shock Drone's distance-charged
  meter ([micro](micro.md)) is a different mechanic and is unaffected.
- REJECTED — **counter-battery** (locating artillery by its fire): too much complexity for the
  fog-of-war system.
- REJECTED — **escorts** as a class: escorting is emergent and needs no definition.
