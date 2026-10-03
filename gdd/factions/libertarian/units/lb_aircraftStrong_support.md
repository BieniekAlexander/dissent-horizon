---
kind: Entity
title: Fabricator
scene: res://scenes/entities/units/lb/lb_aircraftStrong_support.tscn
flavor:
    description: Support vehicle that makes drones
    verbose: Support vehicle that makes drones
build:
  cost: {energy: 1500}
  time: 15
  requires: [lb_tech1]
defense:
  hp: 250
  armour: STRONG
  frame: MECH
senses:
  vision: vision_aerial_large
movement: {speed: RAPID, turn_rate: 90, max_acceleration: 2.33, max_deceleration: -3.5, reverse_speed_ratio: 0.2}
aerial: {mode: HOVERING}
docking: true
ui: {grid: [4, 1], factions: [libertarian]}
---
