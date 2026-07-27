---
kind: AbilityDefinition
title: Overcharge
ui: {grid: [0, 2], factions: [anarchists]}
hud_button: true
column: 2
levels:
  - title: Overcharge
    tier: 3
    cost: 500
    cooldown: 60
    description: Dumps a huge surge into a single DISABLED unit. It can only be aimed at something already stunned — pair it with Global EMP.
    verbose: |
      Worth nothing on its own and decisive after Global EMP: being disabled is a
      requirement of the TARGET, not a damage bonus, so a click that finds no stunned
      unit does nothing at all.

      Any hard stun qualifies, including a Colonial cryogenic freeze — a frozen unit is
      exactly as helpless as an EMPed one.

      The damage is flat rather than a share of the target's health. The pairing already
      guarantees the target cannot escape, so scaling it to size would make the
      combination an unconditional kill on anything.
---
# Overcharge

Sits in the Scavenge column WITHOUT continuing it — separate sanction, shared column.

## Mechanic
Deals a flat amount of damage directly to a single unit that is currently stunned,
bypassing armour.

## Targeting
Any unit, friendly or hostile, that is currently disabled. A unit that is not disabled is
excluded from the candidate search.
