---
kind: Entity
title: Purifier
scene: res://scenes/entities/units/lb/lb_aircraftMedium_antiHeavy.tscn
flavor:
  description: Flying artillery unit
  verbose: Flying artillery unit
build:
  cost: {energy: 1200}
  time: 40
  requires: [lb_tech2]
defense:
  hp: 200
  armour: MEDIUM
  frame: MECH
senses:
  vision: vision_aerial_medium
movement: {speed: QUICK, turn_rate: 60, max_acceleration: 1, max_deceleration: -0.5}
aerial: {mode: FLYING}
docking: true
weapons:
- name: ViperWeapon
  emits:
    id: purifier_emission
    title: Purifier Thing
    scene: res://scenes/entities/projectiles/lb/purifier_thing.tscn
    damage: 15
    damage_type: SIEGE
    speed: BLAZING
    trajectory: LINEAR
    hitscan: false
  split_time: 0.6
  reload_time: 0.6
  clip_size: 1
  reach: ground_range_long
  hits: [ground]
ui: {grid: [2, 1], factions: [libertarian]}
---
