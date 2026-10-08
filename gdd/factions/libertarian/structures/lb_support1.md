---
kind: Entity
title: Reclamator
scene: res://scenes/entities/structures/lb/lb_support1.tscn
flavor:
  description: potato
  verbose: potato
build:
  cost: {energy: 500}
  time: 20
  requires: [lb_barracks]
defense:
  hp: 400
  armour: MEDIUM
  frame: MECH
senses:
  vision: vision_ground_large
footprint: [3, 3]
infrastructure: 50
ui: {grid: [3, 1], factions: [libertarian]}
---
