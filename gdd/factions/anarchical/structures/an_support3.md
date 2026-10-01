---
kind: Entity
title: EMP Device
scene: res://scenes/entities/structures/an/an_support3.tscn
build:
  cost: {energy: 2000}
  time: 60
  requires: [an_tech2]
defense:
  hp: 2000
  armour: MEDIUM
  frame: MECH
senses:
  vision: vision_ground_large
footprint: [3, 3]
abilities:
  - max_charges: 1
    initial_charges: 0
    cooldown: 300
    grants: [global_emp]
infrastructure: -200
ui:
  grid: [3,2]
  factions: [anarchists]
---

