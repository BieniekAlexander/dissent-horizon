---
kind: Entity
title: Chop Shop
scene: res://scenes/entities/structures/an/an_warFactory.tscn
flavor:
  description: potato
  verbose: potato
build:
  cost: {energy: 1200}
  time: 15
  requires: [an_infrastructure]
defense:
  hp: 1200
  armour: MEDIUM
  frame: MECH
senses:
  vision: vision_ground_large
footprint: [4, 4]
trains: [an_mechLight_transport, an_mechMedium_antiBio, an_mechStrong_transport, an_mechMedium_artillery]
infrastructure: -75
ui: {grid: [1, 1], factions: [anarchists], context_grid: [2, 0]}
---

