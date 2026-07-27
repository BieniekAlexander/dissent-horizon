---
kind: Entity
title: Hangar
scene: res://scenes/entities/structures/an/an_airField.tscn
build:
  cost: {energy: 800}
  time: 25
  requires: [an_infrastructure]
defense:
  hp: 1000
  armour: MEDIUM
  frame: MECH
senses:
  vision: vision_ground_large
footprint: [4, 4]
trains: [an_aircraftLight_antiMech, an_aircraftLight_transport, an_aircraftMedium_support]
infrastructure: -75
ui: {grid: [2, 1], factions: [anarchists], context_grid: [3, 0]}
---
 