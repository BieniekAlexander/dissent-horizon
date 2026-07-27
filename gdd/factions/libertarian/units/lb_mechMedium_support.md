---
kind: Entity
title: Liberator
scene: res://scenes/entities/units/lb/lb_mechMedium_support.tscn
flavor:
    description: Support vehicle that heals nearby units and converts enemies
    verbose: Support vehicle that heals nearby units and converts enemies
build:
  cost: {energy: 600}
  time: 15
  requires: [lb_tech2]
defense:
  hp: 250
  armour: MEDIUM
  frame: MECH
senses:
  vision: vision_ground_medium
movement: {speed: BRISK, turn_rate: 150, max_acceleration: 1.5, max_deceleration: -4.5, min_turn_speed_ratio: 0.5}
ui: {grid: [2, 1], factions: [libertarian]}
---

