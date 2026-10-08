---
kind: Entity
title: Academy
scene: res://scenes/entities/structures/cl/cl_tech2.tscn
flavor:
  description: potato
  verbose: potato
build:
  cost: {energy: 1200}
  time: 40
  requires: [cl_warFactory]
defense:
  hp: 1200
  armour: MEDIUM
  frame: MECH
senses:
  vision: vision_ground_large
footprint: [4, 4]
researches: [field_conditioning, gun_drill]
abilities:
  - max_charges: 1
    cooldown: 60
    grants: [gunship]
infrastructure: -50
ui: {grid: [1, 2], factions: [colonial], context_grid: [5, 0]}
---
