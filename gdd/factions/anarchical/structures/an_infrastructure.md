---
kind: Entity
title: Safehouse
scene: res://scenes/entities/structures/an/an_infrastructure.tscn
build:
  cost: {energy: 500}
  time: 20
defense:
  hp: 600
  armour: MEDIUM
  frame: MECH
senses:
  vision: vision_ground_medium
footprint: [2, 2]
garrison: {frames: [BIO], range_bonus: {from: ground_range_medium, to: ground_range_long}}
infrastructure: 50
ui: {grid: [2, 0], factions: [anarchists]}
---
