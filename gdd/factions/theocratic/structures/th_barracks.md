---
kind: Entity
title: th_barracks
scene: res://scenes/entities/structures/th/th_barracks.tscn
build:
  cost: {energy: 300}
  time: 30
  requires: [th_infrastructure]
defense:
  hp: 400
  armour: MEDIUM
  frame: MECH
senses:
  vision: vision_ground_large
footprint: [3, 3]
trains: []
infrastructure: 50
ui: {grid: [0, 1], factions: [theocratic], context_grid: [1, 0]}
---
