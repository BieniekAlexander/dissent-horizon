---
kind: Entity
title: Redoubt
scene: res://scenes/entities/structures/an/an_barracks.tscn
build:
  cost: {energy: 400}
  time: 20
  requires: [an_infrastructure]
defense:
  hp: 750
  armour: MEDIUM
  frame: MECH
senses:
  vision: vision_ground_large
footprint: [3, 3]
trains: [an_bioLight_antiStructure, an_bioMedium_antiMech, an_bioLight_antiBio, an_bioStrong_antiLight, an_bioMedium_support]
infrastructure: -50
ui: {grid: [0, 1], factions: [anarchists], context_grid: [1, 0]}
---

