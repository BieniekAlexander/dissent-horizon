---
kind: Entity
title: mr_war_factory
scene: res://scenes/entities/structures/mr/mr_warFactory.tscn
build:
  cost: {energy: 500}
  time: 30
  requires: [mr_barracks]
defense:
  hp: 400
  armour: MEDIUM
  frame: MECH
senses:
  vision: vision_ground_large
footprint: [4, 4]
trains: []
infrastructure: 50
ui: {grid: [1, 1], factions: [marxist], context_grid: [2, 0]}
---
