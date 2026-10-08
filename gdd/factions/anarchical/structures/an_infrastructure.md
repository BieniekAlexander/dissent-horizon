---
kind: Entity
title: Safehouse
scene: res://scenes/entities/structures/an/an_infrastructure.tscn
flavor:
  description: potato
  verbose: potato
defense:
  armour: MEDIUM
  frame: MECH
senses:
  vision: vision_ground_medium
variants: [nt_building_square, nt_building_long]
garrison: {frames: [BIO], range_bonus: {from: ground_range_medium, to: ground_range_long}}
ui: {grid: [2, 0], factions: [anarchists]}
---
