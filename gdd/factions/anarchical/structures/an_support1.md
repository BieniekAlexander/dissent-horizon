---
kind: Entity
title: Hideout
scene: res://scenes/entities/structures/an/an_support1.tscn
build:
  cost: {energy: 600}
  time: 30
  requires: [an_barracks]
defense:
  hp: 1500
  armour: MEDIUM
  frame: MECH
senses:
  vision: vision_ground_large
footprint: [3, 3]
abilities:
  - max_charges: 1
    cooldown: 180
    grants: [ambush]
infrastructure: -75
ui:
  grid: [1,2]
  factions: [anarchists]
---

