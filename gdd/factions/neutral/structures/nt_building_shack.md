---
kind: Entity
title: shack
scene: res://scenes/entities/structures/nt/nt_building_shack.tscn
family: neutral_building
flavor:
  description: potato
  verbose: potato
build:
  cost: {energy: 300}
  time: 20
defense:
  hp: 600
  armour: MEDIUM
  frame: MECH
senses:
  vision: vision_ground_large
footprint: [2, 2]
garrison: {capacity: 3, frames: [BIO], flushable: true, range_bonus: {from: ground_range_medium, to: ground_range_long}}
infrastructure: 50
---
