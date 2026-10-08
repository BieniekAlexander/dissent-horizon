---
kind: AbilityDefinition
title: Promotion
flavor:
  description: potato
  verbose: potato
ui: {grid: [1, 0], factions: [colonial]}
hud_button: true
column: 0
levels:
  - title: Promotion
    tier: 0
    cost: 125
    cooldown: 60
    description: Grants the first veterancy level to a clicked friendly unit of any type. Only a unit that has not yet earned a level can be promoted this way.
    verbose: |
      Starts a unit's career rather than shortening it. A unit that has already earned a level is not a valid target, so the ranks above Veteran stay earned in combat and no single favourite can be walked up to Heroic with dominion.

      Only an UNBLOODED unit is marked as a target while it is armed; pointing at a unit that has already earned a level targets nothing.
---
# Promotion

## Mechanic
Raises the target's `Veterancy` by exactly one level, from `NONE` to `VETERAN`.

## Targeting
Friendly units only. A unit whose veterancy level is anything other than `NONE` is never
targeted: the armed cursor marks only a unit it can promote, and casting with no unit marked
does nothing and spends no charge.
