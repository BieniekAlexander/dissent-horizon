---
kind: Entity
title: Raven
scene: res://scenes/entities/units/an/an_aircraftLight_transport.tscn
build:
  cost: {energy: 800}
  time: 15
defense:
  hp: 120
  armour: LIGHT
  frame: MECH
senses:
  vision: vision_aerial_large
movement: {speed: QUICK, turn_rate: 180, max_acceleration: 2, max_deceleration: -3, reverse_speed_ratio: 0.35}
aerial: {mode: HOVERING}
docking: true
ui: {grid: [1, 1], factions: [anarchists]}
---
