---
kind: AbilityDefinition
title: Beacon Drop
ui: {grid: [1, 1], factions: [colonial]}
hud_button: true
column: 3
levels:
  - title: Beacon 1
    tier: 1
    cost: 500
    cooldown: 60
    description: Places a firing solution at the target point for 15 seconds. Any {{ cl_defense_antiStructure }} can then shell it from anywhere on the map.
    verbose: |
      The artillery's reach without the walk. A {{ cl_bioLight_antiLight }} can call a
      solution in for free, but it has to get there, hold still for ten seconds and stay
      until the shot lands; this puts one wherever you can see, immediately.

      What you pay for that is a clock: the beacon stands for 15 seconds and is gone
      whether or not a gun used it.

      The beacon is spent by the first shell that uses it, exactly like a spotter's.
  - title: Beacon 2
    tier: 2
    cost: 1000
    cooldown: 60
    description: The same solution, and it now lights the fog around itself (radius 2). Replaces Beacon 1.
    verbose: |
      A blind beacon marks ground you already had eyes on. This one brings its own, so it
      can be dropped into the shroud and show you what it is standing next to — which is
      usually what you wanted to shell.
  - title: Beacon 3
    tier: 3
    cost: 2000
    cooldown: 60
    description: The solution now stands until a shell spends it, rather than expiring. Replaces Beacon 2.
    verbose: |
      Drops the clock. The solution keeps its small sight radius and waits indefinitely,
      so it can be placed before the guns are ready rather than in the same breath.
---
# Beacon Drop

## Mechanic
Places a `Beacon` at the target point, owned by the calling commander — the same entity a
`cl_bioLight_antiLight` calls in with its Spot ability, so the Bombards never need to know
which put it there.

A beacon is **spent by the first bombardment that uses it**. Ground already inside a
permanent beacon range is preferred over a beacon, so a free solution never burns one.

## Progression
| Tier | Lifespan | Sight |
| --- | --- | --- |
| Beacon 1 | 15 seconds | none |
| Beacon 2 | 15 seconds | radius 2 |
| Beacon 3 | until spent | radius 2 |

Sight is a real VisionRange, created only for the tiers that have one — a blind beacon has
no vision node at all rather than a disabled one.
