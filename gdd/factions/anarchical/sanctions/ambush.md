---
kind: AbilityDefinition
title: Ambush
ui: {grid: [0, 1], factions: [anarchists]}
hud_button: true
column: 0
levels:
  - title: Ambush 1
    tier: 1
    cost: 225
    cooldown: 60
    description: Drops 3 × {{ an_bioLight_builder }} at the target point. Use it to reinforce a failing defence, or to open a second front behind the enemy line.
    verbose: |
      The Anarchists' bodies-anywhere sanction. The squad arrives under your control and
      is yours to keep.
  - title: Ambush 2
    tier: 2
    cost: 550
    cooldown: 60
    description: Drops 8 × {{ an_bioLight_builder }} at the target point, replacing Ambush 1.
    verbose: |
      A war band rather than a squad — enough to swing an engagement. Replaces Ambush 1
      outright.
---
# Ambush

## Mechanic
Spawns Irregulars at the target point, owned by the calling commander.

## Progression
Count only: 3 → 8. The piece never changes, which is what makes this the infantry
faction's sanction rather than a shipment. Two levels since 2026-10-02 (it was 4 → 8 → 16):
[sanction-calibration](../../../systems/macroeconomics/pacing/sanction-calibration.md).
