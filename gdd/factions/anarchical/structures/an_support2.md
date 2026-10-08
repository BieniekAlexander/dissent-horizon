---
kind: Entity
title: Distress Signal
scene: res://scenes/entities/structures/an/an_support2.tscn
flavor:
  description: potato
  verbose: potato
build:
  cost: {energy: 1200}
  time: 30
  requires: [an_tech1]
defense:
  hp: 1500
  armour: MEDIUM
  frame: MECH
senses:
  vision: vision_ground_large
footprint: [3, 3]
abilities:
  - max_charges: 1
    cooldown: 60
    grants: [mortar]
infrastructure: -100
ui:
  grid: [2,2]
  factions: [anarchists]
---
