---
kind: Entity
title: mr_air_field
scene: res://scenes/entities/structures/mr/mr_airField.tscn
build:
  cost: {energy: 500}
  time: 30
  requires: [mr_dominion]
defense:
  hp: 400
  armour: MEDIUM
  frame: MECH
senses:
  vision: vision_ground_large
footprint: [4, 4]
trains: []
infrastructure: 50
ui: {grid: [2, 1], factions: [marxist], context_grid: [3, 0]}
---
