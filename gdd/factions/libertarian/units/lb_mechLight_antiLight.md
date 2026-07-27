---
kind: Entity
title: Shock Drone
scene: res://scenes/entities/units/lb/lb_mechLight_antiLight.tscn
flavor:
  description: Attack drone
  verbose: Attack drone, handles lone opponents handily but scales poorly
build:
  cost: {energy: 100}
  time: 10
  requires: []
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
ui: {grid: [0, 1], factions: [libertarian]}
---
- TODO EMP ability, which should require an upgrade
	- applies EMP to enemy units with its melee attack
	- Can be used as a unit's charge when garrisoning it - this system needs to be developed