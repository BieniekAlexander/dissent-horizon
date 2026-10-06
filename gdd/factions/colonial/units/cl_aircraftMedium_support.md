---
kind: Entity
title: Reverence
scene: res://scenes/entities/units/cl/cl_aircraftStrong_support.tscn
flavor:
  description: Cannon spotter aircraft
  verbose: Heavy aircraft that provides signal for cannons
build:
  cost:
    energy: 2000
  time: 15
  requires:
    - cl_tech2
defense:
  hp: 700
  armour: MEDIUM
  frame: MECH
senses:
  vision: vision_aerial_large
movement:
  speed: RAPID
  turn_rate: 90
  max_acceleration: 2.33
  max_deceleration: -3.5
  reverse_speed_ratio: 0.2
aerial: {mode: HOVERING}
docking: true
beacon: 5
ui:
  grid:
    - 2
    - 1
  factions:
    - colonial
---
## Visuals
- Like a Science Vessel in Starcraft: Brood War. Essentially, it can be a floating cylinder for now.
# Notes
- `beacon_range: 5` is the "provides signal for cannons" line made mechanical: everything
  within 5 units of it is permanently bombardable by friendly Bombards, and unlike a
  beacon the range is never spent. A mobile firing solution the player flies to wherever
  the guns are needed.
