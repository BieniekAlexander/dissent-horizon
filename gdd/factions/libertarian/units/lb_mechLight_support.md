---
kind: Entity
title: Point Defense Drone
scene: res://scenes/entities/units/lb/lb_mechLight_support.tscn
flavor:
  description: Point Defense Drone
  verbose: Point Defense Drone, equipped with an anti-rocket lazer
build:
  cost: {energy: 500}
  time: 10
  requires: [lb_tech2]
defense:
  hp: 100
  armour: LIGHT
  frame: MECH
senses:
  vision: vision_ground_medium
movement: {speed: SLOW, turn_rate: 1080, min_turn_speed_ratio: 0}
weapons:
- name: Zap
  melee_damage: 35
  melee_damage_type: LEAD
  split_time: 0.75
  reload_time: 0.75
  clip_size: 1
  reach: ground_range_melee
  hits: [ground]
ui: {grid: [3, 1], factions: [libertarian]}
---
