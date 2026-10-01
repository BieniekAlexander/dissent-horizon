---
kind: Entity
title: long building
scene: res://scenes/entities/structures/nt/nt_building_long.tscn
family: neutral_building
build:
  cost: {energy: 500}
  time: 25
defense:
  hp: 1000
  armour: MEDIUM
  frame: MECH
senses:
  vision: vision_ground_large
footprint: [3, 5]
garrison: {capacity: 5, range_bonus: {from: ground_range_medium, to: ground_range_long}}
infrastructure: 75
---
