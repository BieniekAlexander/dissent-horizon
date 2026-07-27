---
kind: AbilityDefinition
title: Ambush
ui: {grid: [0, 1], factions: [anarchists]}
hud_button: true
column: 0
levels:
  - title: Ambush 1
    tier: 1
    cost: 250
    cooldown: 60
    description: Drops 4 × {{ an_bioLight_builder }} at the target point. Use it to reinforce a failing defence, or to open a second front behind the enemy line.
    verbose: |
      The Anarchists' bodies-anywhere sanction. The squad arrives under your control and
      is yours to keep.
  - title: Ambush 2
    tier: 2
    cost: 500
    cooldown: 60
    description: Drops 8 × {{ an_bioLight_builder }} at the target point, replacing Ambush 1.
    verbose: 'Twice the squad for the same click. Replaces Ambush 1 outright.'
  - title: Ambush 3
    tier: 3
    cost: 500
    cooldown: 60
    description: Drops 16 × {{ an_bioLight_builder }} at the target point, replacing Ambush 2.
    verbose: |
      A full war band dropped in one go — enough to decide an engagement outright, which
      is what the bottom of the Ambush column is for.
---
# Ambush

## Mechanic
Spawns Irregulars at the target point, owned by the calling commander.

## Progression
Count only: 4 → 8 → 16. The piece never changes, which is what makes this the infantry
faction's sanction rather than a shipment.
