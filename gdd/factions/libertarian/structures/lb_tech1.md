---
kind: Entity
title: Controller
scene: res://scenes/entities/structures/lb/lb_tech1.tscn
flavor:
  description: potato
  verbose: potato
build:
  cost:
    energy: 1200
  time: 30
  requires:
    - lb_barracks
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
  grid: [0, 2]
  factions: [libertarian]
---
