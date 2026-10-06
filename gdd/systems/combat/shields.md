---
title: Shields, freeze and frost fields
type: system-note
---

# Shields, freeze and frost fields

Decided 2026-10-05. Cryogenics is never a damage type: it is a status effect, and what it
does to damage it does through a shield.

## Shields

A **shield** is a pool of hit points standing over a piece's `Defense`. Damage meets every
shield before it meets the piece's own hit points.

- **Each layer resists on its own terms.** A shield may name its own armour class and frame,
  or fall through to the host's, independently for each. Damage is resolved against each
  layer's multipliers separately.
- **What a shield cannot hold passes on as the base damage it did not absorb.** A 400-damage
  shot meeting a 150-hp shield that takes it at ×0.6 spends 250 of its base breaking the
  shield, and the remaining 150 base meets the host at the host's own multipliers. Passing on
  the *effective* overflow instead would let one layer's resistance leak into the next.
- **One shield per type.** `Shield.Type` names the kinds; a piece holds at most one of each.
  Shields are met in type order.
- **Reapplying a shield type takes the larger of each:** hit points, and the remaining time of
  whatever granted it. A 100-hp shield with 1.2 s left, met by a 150-hp one of 1.0 s, becomes
  150 hp with 1.2 s.
- **The grant owns the duration.** A shield is only a pool; the status effect that grants it
  decides how long it stands and ends it.
- **No exceptions are defined yet.** Every source of damage meets shields first, except what
  writes hit points directly: the Anarchical Overcharge, which bypasses armour and shields
  alike. It can only be cast on an EMP'd unit, never on a merely frozen one.

TODO: how a shield is drawn. Today only the Freeze's own tint and badge show one; a shield's
remaining hit points are not displayed anywhere.

## Freeze

The freeze is a stun plus a CRYO shield: the piece can take no action at all, and 150 hit
points of ice take damage before it does. The ice resists as `STRONG` armour and falls
through to the host's frame. It lasts 10 seconds, however it was applied
(`FreezeStatusEffect.FREEZE_SECONDS`, one constant for every applicator).

- **Breaking the ice ends the freeze.** Focused fire is the answer to a frozen piece.
- **STRONG pieces cannot be frozen.** Cryogenics does not take on the heaviest armour. That
  is also why an Avalanche, which is STRONG, never freezes itself in its own field.
- **Structures can be frozen by the Freeze ordnance**, but not by a frost field.

It is applied by:

| Applicator | How |
|---|---|
| Freeze ordnance | immediately, on the clicked unit or structure |
| Avalanche | its frost field, below |
| Blizzard | a frost field after a 10 s gathering, below |

## Frost fields

A frost field is a lingering area that freezes the units standing in it (`FrostField`, a
component on an emission).

- **Exposure:** a unit freezes after 2 seconds in the field. Time outside drains exposure back
  at the rate it built, so a unit cannot cross in short hops.
- **The field holds a freeze at full time** for as long as the unit stays inside, but never
  mends its ice: refreshing the hit points every tick would make a frozen unit unbreakable for
  the field's whole life. A freeze broken inside the field starts that unit's exposure over.
- **It freezes every unit, friend or foe.** Structures and STRONG pieces are untouched.

**The Avalanche** must hold its target for 3 seconds before it fires (the weapon's
`startup_time`). Its shot stands an `aoe_large` field where it lands, lasting 5 seconds, and
the Avalanche is free to move while it reloads for 15 seconds. The reload outlasts a freeze
and its field together, so one Avalanche cannot keep a group frozen on its own: a unit it
froze thaws with time to walk clear before the next shell lands. Locking down an army takes
several Avalanches and timing.

It fires on its own like any armed piece; holding fire is how a player keeps it out of a
fight its own side is in.

**The Blizzard** is an ordnance that stands a `blizzard_field` at the target point. It gathers
for 10 seconds, the storm's warning, and is then an `aoe_huge` field for 10 seconds.

Both draw falling, swirling snowflakes over the field (`Snowfall`), sized to its radius, and a
thin white circle on the ground at exactly the field's edge (`GroundRing`, read from the
field's HitShape). The Blizzard's circle shows through the gathering too, as the warning of
where the storm will stand.
