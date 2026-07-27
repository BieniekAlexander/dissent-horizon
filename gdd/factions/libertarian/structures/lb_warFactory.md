---
kind: Entity
title: LI War Factory
scene: res://scenes/entities/structures/lb/lb_warFactory.tscn
build:
  cost: {energy: 500}
  time: 30
  requires: [lb_barracks]
defense:
  hp: 400
  armour: MEDIUM
  frame: MECH
senses:
  vision: vision_ground_large
footprint: [4, 4]
trains: [lb_mechLight_antiLight1, lb_mechLight_antiStrong, lb_mechMedium_antiLight, lb_aircraftStrong_support, lb_mechMedium_support]
infrastructure: 50
ui: {grid: [1, 2], factions: [libertarian], context_grid: [2, 0]}
---
