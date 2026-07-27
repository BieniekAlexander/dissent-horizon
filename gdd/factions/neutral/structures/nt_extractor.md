---
kind: Entity
title: Extractor
scene: res://scenes/entities/structures/nt/nt_extractor.tscn
build:
  cost: {energy: 500}
  time: 20
  requires: []
defense:
  hp: 500
  armour: MEDIUM
  frame: MECH
senses:
  vision: vision_ground_medium
footprint: [2, 2]
extractor: true
infrastructure: -50
ui: {grid: [0, 0], factions: [neutral]}
---
