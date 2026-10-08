---
kind: Entity
title: Annex
scene: res://scenes/entities/structures/cl/cl_support1.tscn
flavor:
  description: potato
  verbose: potato
build:
  cost:
    energy: 500
  time: 20
  requires:
    - cl_tech1
defense:
  hp: 500
  armour: MEDIUM
  frame: MECH
senses:
  vision: vision_ground_large
footprint:
  - 4
  - 4
infrastructure: -50
ui:
  grid:
    - 2
    - 2
  factions:
    - colonial
---
