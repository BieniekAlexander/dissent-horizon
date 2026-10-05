---
kind: Entity
title: Outpost
scene: res://scenes/entities/structures/tc/tc_commandCenter.tscn
build:
  cost:
    energy: 1500
  time: 30
  requires: []
defense:
  hp: 3000
  armour: STRONG
  frame: MECH
senses:
  vision: vision_ground_huge
footprint: [8, 8]
trains:
  - tc_bioLight_builder
  - tc_mechMedium_infrastructure
infrastructure: 100
ui:
  grid: [1, 0]
  context_grid: [0, 0]
  factions: [technocracy]
---
