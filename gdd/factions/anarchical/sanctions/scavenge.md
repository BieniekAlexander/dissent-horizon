---
kind: AbilityDefinition
title: Scavenge
passive: true
valence: BOON
column: 2
levels:
  - title: Scavenge 1
    tier: 0
    cost: 150
    description: Every enemy unit or structure you destroy pays back 10% of its build cost in energy. Always on once unlocked — there is nothing to deploy.
    verbose: |
      A STANDING benefit rather than a sanction you fire: unlocking it is the whole
      thing. It never appears on the deploy bar and has no cooldown.

      The bounty is paid to whoever landed the killing blow, so it cannot be earned from
      your own losses, from a unit that starves, or from one scuttled deliberately.
    kill_bounty: 0.1
  - title: Scavenge 2
    tier: 1
    cost: 300
    description: Every enemy kill pays back 20% of its build cost in energy, replacing Scavenge 1. Always on once unlocked.
    verbose: 'Replaces Scavenge 1 rather than adding to it — the rate becomes 20%, not 30%.'
    kill_bounty: 0.2
  - title: Scavenge 3
    tier: 2
    cost: 600
    description: Every enemy kill pays back 30% of its build cost in energy, replacing Scavenge 2. Always on once unlocked.
    verbose: 'The full expression of the faction''s scavenging theme: a third of everything you destroy comes back as energy.'
    kill_bounty: 0.3
---
# Scavenge

## Mechanic
A **passive**: no deployment, no aim point, no cooldown. While owned, destroying an enemy
unit or structure pays the killer's commander a share of that piece's energy build cost.

## Attribution
Paid to the commander of the unit that landed the killing blow, and only for ENEMY
pieces. A piece with no price in the technology data (neutral scenery, scenario-only
entities) pays nothing.

## Progression
Rate only: 10% → 20% → 30%. Each tier REPLACES the one before it.
