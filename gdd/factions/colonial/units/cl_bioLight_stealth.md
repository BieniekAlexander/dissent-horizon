---
kind: Entity
title: sleeper
scene: res://scenes/entities/units/cl/cl_bioLight_stealth.tscn
build:
  cost:
    energy: 600
  time: 15
  requires:
    - cl_tech1
defense:
  hp: 120
  armour: LIGHT
  frame: BIO
senses:
  vision: vision_ground_small
  detection: detection_small
movement:
  speed: SLOW
  turn_rate: 1080
  min_turn_speed_ratio: 0
abilities:
  - max_charges: 1
    cooldown: 15
    grants:
      - spot
stealth: true
plants_beacons: true
ui:
  grid:
    - 3
    - 1
  factions:
    - colonial
---
## Visuals
- Maybe a copy of the irregular model, but with a trangular torso instead of a rectangular one
# Notes
- `stealth: true` gives the piece a `Stealth` component. Presence is the whole mechanic — the component has no exports; what REVEALS it is another piece's `detection:` radius.
- Unarmed — nothing here claims a combat role, unlike Clipper's "good against light armor"
- **Plants beacons** with the same [[spot|Spot]] order a Recruit uses, in its own way
  (`plants_beacons: true`): it walks to the point itself, takes 3 seconds to plant, and
  leaves the ground beacon a Beacon Drop places — then moves on, free. The beacon stands
  until a Bombard spends it or an enemy repairs it away, and calls no automatic fire. The
  15 s cooldown runs from the plant. See
  [bombardment](../../../systems/combat/bombardment.md) §Planting a beacon.
