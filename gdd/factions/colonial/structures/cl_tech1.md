---
kind: Entity
title: Operations Center
scene: res://scenes/entities/structures/cl/cl_tech1.tscn
build:
  cost: {energy: 1200}
  time: 25
  requires: [cl_barracks]
defense:
  hp: 1000
  armour: MEDIUM
  frame: MECH
senses:
  vision: vision_ground_large
footprint: [4, 4]
researches: [advanced_targetting]
infrastructure: -50
ui: {grid: [0, 2], factions: [colonial], context_grid: [4, 0]}
---
