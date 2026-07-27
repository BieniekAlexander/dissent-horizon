---
kind: Entity
title: Mainframe
scene: res://scenes/entities/structures/lb/lb_tech2.tscn
build:
  cost:
    energy: 2000
  time: 30
  requires:
    - lb_warFactory
defense:
  hp: 400
  armour: MEDIUM
  frame: MECH
senses:
  vision: vision_ground_large
footprint:
  - 4
  - 4
infrastructure: 50
ui:
  grid: [2, 1]
  factions: [libertarian]
---
