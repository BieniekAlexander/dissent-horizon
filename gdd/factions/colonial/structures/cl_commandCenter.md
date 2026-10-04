---
kind: Entity
title: Citadel
scene: res://scenes/entities/structures/cl/cl_commandCenter.tscn
build:
  cost:
    energy: 1500
  time: 30
  requires: []
defense:
  hp: 3000
  armour: STRONG
  frame: MECH
senses:
  vision: vision_ground_huge
footprint:
  - 8
  - 8
trains:
  - cl_mechLight_dominionGen
  - cl_bioLight_builder
abilities:
  - max_charges: 1
    initial_charges: 0
    cooldown: 60
    grants:
      - beacon
      - freeze
      - promotion
      - scan
infrastructure: 100
ui:
  grid:
    - 1
    - 0
  context_grid:
    - 0
    - 0
  factions:
    - colonial
---

