---
kind: Entity
title: th_dominion
scene: res://scenes/entities/structures/th/th_dominion.tscn
flavor:
  description: potato
  verbose: potato
build:
  cost:
    energy: 250
  time: 15
  requires:
    - th_infrastructure
defense:
  hp: 400
  armour: LIGHT
  frame: MECH
senses:
  vision: vision_ground_medium
footprint:
  - 1
  - 1
infrastructure: 500
ui:
  grid:
    - 2
    - 0
  factions:
    - theocratic
---
