---
kind: Entity
title: Barracks
scene: res://scenes/entities/structures/cl/cl_barracks.tscn
flavor:
  description: potato
  verbose: potato
build:
  cost:
    energy: 300
  time: 10
  requires:
    - cl_infrastructure
defense:
  hp: 600
  armour: MEDIUM
  frame: MECH
senses:
  vision: vision_ground_large
footprint:
  - 4
  - 4
trains:
  - cl_bioLight_antiLight
  - cl_bioLight_antiMech
  - cl_bioMedium_antiStrong
  - cl_bioLight_stealth
infrastructure: -50
ui:
  grid:
    - 0
    - 1
  context_grid:
    - 1
    - 0
  factions:
    - colonial
---
