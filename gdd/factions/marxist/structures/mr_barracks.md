---
kind: Entity
title: mr_barracks
scene: res://scenes/entities/structures/mr/mr_barracks.tscn
build:
  cost: {energy: 300}
  time: 30
  requires: [mr_infrastructure]
defense:
  hp: 400
  armour: MEDIUM
  frame: MECH
senses:
  vision: vision_ground_large
footprint: [3, 3]
trains: []
infrastructure: 50
ui: {grid: [0, 1], factions: [marxist], context_grid: [1, 0]}
---
