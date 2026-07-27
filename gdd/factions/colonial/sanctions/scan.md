---
kind: AbilityDefinition
title: Scan
ui: {grid: [2, 0], factions: [colonial]}
hud_button: true
column: 1
levels:
  - title: Scan 1
    tier: 0
    cost: 500
    cooldown: 60
    description: Reveals the fog of war within 10 units of the target point for 15 seconds, then fades. Scouting without risking a unit.
    verbose: |
      The one family that may be aimed into ground you cannot see — a reveal that could
      only be pointed at what you already had eyes on would be useful precisely where it
      is not needed.

      The reveal is a real vision source for its lifetime, not a one-off snapshot, so
      anything that moves through the circle is seen while it is up.
    needs_vision: false
  - title: Scan 2
    tier: 1
    cost: 500
    cooldown: 60
    description: Reveals the fog around the target point for 15 seconds and exposes any stealthed units caught in it, replacing Scan 1.
    verbose: |
      The same circle, now with detection: stealthed units inside it are revealed for as
      long as the scan lasts. The counter to an opponent leaning on stealth.
    needs_vision: false
  - title: Scan 3
    tier: 2
    cost: 500
    cooldown: 60
    description: Leaves a permanent eye over the target point — the same reveal and stealth detection, held indefinitely. Replaces Scan 2.
    verbose: |
      A hovering observer that never expires. It cannot be commanded or selected, and it
      watches the ground it was placed over for the rest of the match, unless the enemy
      shoots it down.
    needs_vision: false
---
# Scan

## Mechanic
Places a vision source at the target point for a fixed lifetime — permanently at Scan 3.
It contributes fog clearing exactly as a unit's vision does, and from Scan 2 also reveals
stealthed enemies within the same radius.

## Targeting
The whole family waives the fog gate (`needs_vision: false`), which is the point of it.

## Notes
Every tier's observer is the Recon Drone: uncommandable and unselectable, but a real
target that anti-air can shoot down, which ends the reveal.
