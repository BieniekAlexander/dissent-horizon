---
kind: Entity
title: Emission Bay
scene: res://scenes/entities/structures/lb/lb_airField.tscn
build:
  cost: {energy: 500}
  time: 30
  requires: [lb_dominion]
defense:
  hp: 400
  armour: MEDIUM
  frame: MECH
senses:
  vision: vision_ground_large
footprint: [4, 4]
trains: [lb_aircraftLight_antiAir, lb_aircraftMedium_antiMech, lb_aircraftMedium_antiHeavy]
infrastructure: 50
ui: {grid: [1, 1], factions: [libertarian], context_grid: [3, 0]}
---
