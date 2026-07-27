---
kind: Entity
title: Stockpile
scene: res://scenes/entities/structures/an/an_tech1.tscn
build:
  cost: {energy: 1200}
  time: 25
  requires: [an_warFactory]
defense:
  hp: 1000
  armour: MEDIUM
  frame: MECH
senses:
  vision: vision_ground_large
footprint: [3, 3]
infrastructure: -50
ui: {grid: [3, 1], factions: [anarchists]}
---
