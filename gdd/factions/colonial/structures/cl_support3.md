---
kind: Entity
title: Storm Cell
scene: res://scenes/entities/structures/cl/cl_support3.tscn
flavor:
  description: potato
  verbose: potato
build:
  cost: {energy: 2000}
  time: 30
  requires: [cl_tech2]
defense:
  hp: 1500
  armour: STRONG
  frame: MECH
senses:
  vision: vision_ground_large
footprint: [5, 5]
abilities:
  - max_charges: 1
    initial_charges: 0
    cooldown: 240
    grants: [blizzard]
infrastructure: -200
ui: {grid: [4, 2], factions: [colonial]}
---
