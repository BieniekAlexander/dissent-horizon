---
kind: Entity
title: large building
scene: res://scenes/entities/structures/nt/nt_building_large.tscn
family: neutral_building
build:
  cost: {energy: 750}
  time: 35
defense:
  hp: 1500
  armour: MEDIUM
  frame: MECH
senses:
  vision: vision_ground_large
footprint: [8, 5]
garrison: {range_bonus: {from: ground_range_medium, to: ground_range_long}}
infrastructure: 100
---
