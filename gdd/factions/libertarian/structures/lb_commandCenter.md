---
kind: Entity
title: Shard
scene: res://scenes/entities/structures/lb/lb_commandCenter.tscn
build:
  cost:
    energy: 300
  time: 60
defense:
  hp: 400
  armour: STRONG
  frame: MECH
senses:
  vision: vision_ground_huge
footprint:
  - 4
  - 4
trains:
  - lb_aircraftLight_builder
infrastructure: 100
ui:
  grid: [1, 0]
  context_grid: [0, 0]
  factions:
    - libertarian
---
