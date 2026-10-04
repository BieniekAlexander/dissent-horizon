---
kind: Entity
title: Interceptor
scene: res://scenes/entities/units/lb/lb_aircraftLight_antiAir.tscn
flavor:
  description: Flying anti-aircraft unit
  verbose: Flying anti-aircraft unit
build:
  cost: {energy: 500}
  time: 40
  requires: []
defense:
  hp: 200
  armour: MEDIUM
  frame: MECH
senses:
  vision: vision_aerial_medium
movement: {speed: HYPER, turn_rate: 343, max_acceleration: 7.62, max_deceleration: -3.81}
aerial: {mode: FLYING}
docking: true
weapons:
- name: InterceptorWeapon
  emits:
    id: interceptor_emission
    title: Interceptor Thing
    scene: res://scenes/entities/projectiles/lb/interceptor_emission.tscn
    damage: 10
    damage_type: SIEGE
    speed: SUPERSONIC
    trajectory: LINEAR
    hitscan: false
  split_time: 0.4
  reload_time: 100
  clip_size: 50
  reach: air_range_long
  hits: [air]
ui: {grid: [0, 1], factions: [libertarian]}
---
