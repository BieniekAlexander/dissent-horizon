---
kind: Entity
title: Production Yard
scene: res://scenes/entities/structures/cl/cl_warFactory.tscn
build:
  cost: {energy: 2000}
  time: 15
  requires: [cl_barracks]
defense:
  hp: 400
  armour: MEDIUM
  frame: MECH
senses:
  vision: vision_ground_large
footprint: [4, 4]
trains: [cl_mechMedium_antiLight, cl_mechMedium_antiMech, cl_mechStrong_support]
infrastructure: -75
ui: {grid: [1, 1], factions: [colonial], context_grid: [2, 0]}
---
