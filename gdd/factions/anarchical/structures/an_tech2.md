---
kind: Entity
title: Clandestine Lab
scene: res://scenes/entities/structures/an/an_tech2.tscn
build:
  cost: {energy: 2000}
  time: 40
  requires: [an_airField]
defense:
  hp: 1200
  armour: MEDIUM
  frame: MECH
senses:
  vision: vision_ground_medium
footprint: [1, 4]
abilities:
  - max_charges: 1
    cooldown: 60
    grants: [overcharge]
infrastructure: -75
ui: {grid: [4, 1], factions: [anarchists]}
---

