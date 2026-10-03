---
kind: Entity
title: Harpy
scene: res://scenes/entities/units/lb/lb_aircraftLight_antiMech.tscn
flavor:
    description: light flying unit, good against mechanical targets
    verbose: light flying unit that's good against mechanical targets, but can only shoot grounded targets
build:
  cost: {energy: 250}
  time: 15
  requires: [lb_tech1]
defense:
  hp: 120
  armour: LIGHT
  frame: MECH
senses:
  vision: vision_aerial_large
movement: {speed: BLAZING, turn_rate: 270, max_acceleration: 9.45, max_deceleration: -11.8, reverse_speed_ratio: 0.6}
aerial: {mode: HOVERING}
docking: true
weapons:
  - name: Weapon
    emits: sam_missile         # shared with th e Colonial SAM site for now (cl_defense_antiAircraft)
    split_time: .33
    reload_time: 3
    clip_size: 5
    reach: {ground: air_range_short}
    hits: [ground]
ui: {grid: [1, 1], factions: [libertarian]}
---
