---
kind: Entity
title: Assembler
scene: res://scenes/entities/structures/lb/lb_barracks.tscn
build:
  cost: {energy: 300}
  time: 30
  requires: [lb_infrastructure]
defense:
  hp: 400
  armour: MEDIUM
  frame: MECH
senses:
  vision: vision_ground_large
footprint: [3, 3]
trains: [lb_mechLight_antiLight, lb_aircraftMedium_antiBio, lb_aircraftLight_antiMech, lb_mechLight_support]
infrastructure: 50
ui: {grid: [0, 1], factions: [libertarian], context_grid: [1, 0]}
---
