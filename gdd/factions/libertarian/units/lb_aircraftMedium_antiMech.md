---
kind: Entity
title: Viper
scene: res://scenes/entities/units/lb/lb_aircraftMedium_antiMech.tscn
flavor:
  description: Flying anti-mech unit
  verbose: Flying anti-mech unit
build:
  cost: {energy: 500}
  time: 20
  requires: []
defense:
  hp: 200
  armour: MEDIUM
  frame: MECH
senses:
  vision: vision_aerial_medium
movement: {speed: SWIFT, turn_rate: 140, max_acceleration: 2.33, max_deceleration: -1.16}
aerial: {mode: FLYING}
docking: true
weapons:
- name: ViperWeapon
  emits:
    id: viper_emission
    title: Sentinel Thing
    scene: res://scenes/entities/projectiles/lb/sentinel_thing.tscn
    damage: 15
    damage_type: EXPLOSIVE
    speed: SCORCHING
    trajectory: LINEAR
    hitscan: true
  split_time: 0.6
  reload_time: 0.6
  clip_size: 1
  reach: ground_range_long
  hits: [ground]
ui: {grid: [1, 1], factions: [libertarian]}
---
