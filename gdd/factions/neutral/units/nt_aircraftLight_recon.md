---
kind: Entity
title: Recon Drone
scene: res://scenes/entities/nt_aircraftLight_recon.tscn
editor_description: Observation drone left by a Scan sanction. Cannot move or be ordered.
commandable: false
flavor:
  description: Observation drone. Watches the ground it was placed over; cannot move or be ordered.
  verbose: |
    Left behind by a Scan sanction, or by a scenario revealing a region. It holds position,
    clears fog for its owner and — on the later Scan tiers — exposes stealthed units inside
    its radius.

    It is a real target: 50 HP, light armour, mech frame. Shoot it down and the reveal ends.
defense:
  hp: 50
  armour: LIGHT
  frame: MECH
senses:
  vision: vision_aerial_large
movement: {speed: ZERO, turn_rate: 0}
aerial: {mode: HOVERING}
docking: true
---

# Recon Drone

The eye a Colonial **Scan** sanction leaves behind, and the vision source
`EventRevealRegion` places when a scenario reveals a region.

## Not commandable, but attackable
- **Cannot move** — `speed: ZERO`. The HOVERING mode is not about travel: it is what puts the
  drone on the anti-air targeting layer so it can be shot at all.
- **Cannot be ordered** — its inherited `Selectable` has its collision layer cleared, so
  no selection query ever finds it.
- **Can be destroyed** — 50 HP, light armour, mech frame. Before it had a `Defense` it was
  unkillable, and a permanent Scan 3 eye was an unanswerable reveal.

## No aggro, no weapon
`aggro: 0` and no `weapons:` block: it watches and nothing else.

## Notes
- No `ui:` key — it is never built or trained, only placed by a sanction or a scenario
  event, so it has no command-grid button. Its economy figures are the importer's
  placeholder defaults and mean nothing.
