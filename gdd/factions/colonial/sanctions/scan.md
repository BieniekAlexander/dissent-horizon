---
kind: AbilityDefinition
title: Scan
ui: {grid: [2, 0], factions: [colonial]}
hud_button: true
column: 1
levels:
  - title: Scan 1
    tier: 0
    cost: 250
    cooldown: 60
    description: Leaves a permanent observer over the target point, revealing the fog within 24 units. Scouting without risking a unit — until the enemy shoots it down.
    verbose: |
      The one family that may be aimed into ground you cannot see — a reveal that could
      only be pointed at what you already had eyes on would be useful precisely where it
      is not needed.

      The observer never expires. It is a real vision source, so anything that moves
      through its circle is seen, and it is a real target: anti-air can shoot it down,
      which ends the reveal.
    needs_vision: false
  - title: Scan 2
    tier: 1
    cost: 450
    cooldown: 60
    description: The same permanent observer, now also exposing stealthed units within 16 units of it. Replaces Scan 1.
    verbose: |
      Adds detection to the observer: stealthed units near it are revealed for as long as
      it stands. The counter to an opponent leaning on stealth.
    needs_vision: false
---
# Scan

## Mechanic
Places a permanent observer at the target point. It contributes fog clearing exactly as a
unit's vision does (radius 24, `vision_ground_large`), and at Scan 2 also reveals stealthed
enemies within 16 (`detection_medium`).

Two levels since 2026-10-02 (it was three, with 15-second reveals at the first two):
[sanction-calibration](../../../systems/macroeconomics/pacing/sanction-calibration.md)
§Scan. TODO: whether Scan 2's observer should itself be stealthed, and its detection radius,
are open.

## Targeting
The whole family waives the fog gate (`needs_vision: false`), which is the point of it.

## Notes
Every level's observer is the Recon Drone: uncommandable and unselectable, but a real
target that anti-air can shoot down, which ends the reveal.
