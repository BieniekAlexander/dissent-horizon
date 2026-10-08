---
kind: Entity
title: Supply Beacon
scene: res://scenes/entities/structures/cl/cl_support2.tscn
flavor:
  description: potato
  verbose: potato
build:
  cost: {energy: 2000}
  time: 20
  requires: [cl_airField]
defense:
  hp: 600
  armour: MEDIUM
  frame: MECH
senses:
  vision: vision_ground_large
footprint: [4, 4]
abilities:
  - max_charges: 1
    initial_charges: 0
    cooldown: 60
    grants: [drop]
infrastructure: -100
ui: {grid: [3, 2], factions: [colonial]}
---
