---
kind: Entity
title: sleeper
scene: res://scenes/entities/units/cl/cl_bioLight_stealth.tscn
build:
  cost:
    energy: 600
  time: 15
  requires:
    - cl_tech2
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
stealth: true
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
- Beacon-placing is not built — no such mechanic exists anywhere in the codebase yet
