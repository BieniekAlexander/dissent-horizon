---
kind: Entity
title: Surveyor
scene: res://scenes/entities/units/an/tc_mechMedium_infrastructure.tscn
build:
  cost: {energy: 500}
  time: 25
  requires: []
defense:
  hp: 300
  armour: MEDIUM
  frame: MECH
senses:
  vision: vision_aerial_large
movement: {speed: QUICK, turn_rate: 180, max_acceleration: 2, max_deceleration: -3, reverse_speed_ratio: 0.35}
aerial: {mode: HOVERING}
docking: true
infrastructure: 75
ui: {grid: [1, 1], factions: [technocracy]}
---

