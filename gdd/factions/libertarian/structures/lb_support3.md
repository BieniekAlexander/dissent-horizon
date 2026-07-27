---
kind: Entity
title: Absolution
scene: res://scenes/entities/structures/lb/lb_support3.tscn
build:
  cost: {energy: 500}
  time: 20
  requires: [lb_tech2]
defense:
  hp: 400
  armour: MEDIUM
  frame: MECH
senses:
  vision: vision_ground_large
footprint: [3, 3]
infrastructure: 50
ui: {grid: [5, 1], factions: [libertarian]}
---
