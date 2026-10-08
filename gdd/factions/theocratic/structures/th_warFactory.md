---
kind: Entity
title: th_war_factory
scene: res://scenes/entities/structures/th/th_warFactory.tscn
flavor:
  description: potato
  verbose: potato
build:
  cost: {energy: 500}
  time: 30
  requires: [th_barracks]
defense:
  hp: 400
  armour: MEDIUM
  frame: MECH
senses:
  vision: vision_ground_large
footprint: [4, 4]
trains: []
infrastructure: 50
ui: {grid: [1, 1], factions: [theocratic], context_grid: [2, 0]}
---
