---
kind: Entity
title: Sentinel
scene: res://scenes/entities/units/lb/lb_aircraftMedium_antiBio.tscn
flavor:
  description: Flying anti-bio unit, detects stealth units
  verbose: Flying anti-bio unit, detects stealth units
build:
  cost: {energy: 300}
  time: 15
  requires: []
defense:
  hp: 200
  armour: MEDIUM
  frame: MECH
senses:
  vision: vision_aerial_large
  detection: detection_small
movement: {speed: RAPID, turn_rate: 90, max_acceleration: 2.33, max_deceleration: -3.5, reverse_speed_ratio: 0.2}
aerial: {mode: HOVERING}
docking: true
weapons:
- name: SentinelSonicWeapon
  emits: viper_emission
  split_time: 0.6
  reload_time: 0.6
  clip_size: 1
  reach: ground_range_long
  hits: [ground]
ui: {grid: [2, 1], factions: [libertarian]}
---
