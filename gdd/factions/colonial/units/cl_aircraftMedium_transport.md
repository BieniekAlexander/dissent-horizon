---
kind: Entity
title: caravel
scene: res://scenes/entities/units/cl/cl_aircraftMedium_transport.tscn
flavor:
  description: large, durable air transport
  verbose: large, durable air transport
build:
  cost:
    energy: 500
  time: 25
  requires: []
defense:
  hp: 180
  armour: MEDIUM
  frame: MECH
senses:
  vision: vision_aerial_large
movement:
  speed: QUICK
  turn_rate: 180
  max_acceleration: 2
  max_deceleration: -3
  reverse_speed_ratio: 0.35
aerial: {mode: HOVERING}
docking: true
garrison:
  capacity: 8
ui:
  grid:
    - 3
    - 1
  factions:
    - colonial
---
## Visuals
- can use the former model of the Petrel - please rename it to caravel
# Notes
- `garrison: {capacity: 8}` — the masks stay at their defaults (any frame, any armour, grounded only). Capacity counts OCCUPANCY, not heads, so a Collective (`occupancy_size: 2`) takes two of the eight.