---
kind: Entity
title: building
scene: res://scenes/entities/structures/nt/nt_building_square.tscn
family: neutral_building
flavor:
  description: potato
  verbose: potato
build:
  cost: {energy: 500}
  time: 25
defense:
  hp: 1000
  armour: MEDIUM
  frame: MECH
senses:
  vision: vision_ground_large
footprint: [4, 4]
garrison: {capacity: 5, frames: [BIO], range_bonus: {from: ground_range_medium, to: ground_range_long}}
infrastructure: 75
---
