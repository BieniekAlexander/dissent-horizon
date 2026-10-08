---
kind: Entity
title: Pacific Enforcer
scene: res://scenes/entities/structures/lb/lb_support2.tscn
flavor:
  description: potato
  verbose: potato
build:
  cost: {energy: 500}
  time: 20
  requires: [lb_tech1]
defense:
  hp: 400
  armour: MEDIUM
  frame: MECH
senses:
  vision: vision_ground_large
footprint: [3, 3]
infrastructure: 50
ui: {grid: [4, 1], factions: [libertarian]}
---
