---
kind: Entity
title: MDC
scene: res://scenes/entities/units/lb/lb_mechMedium_antiLight.tscn
flavor:
    description: Mech unit, weak alone but can be augmented with drones
    verbose: Mobile Drone Chassis
build:
  cost: {energy: 600}
  time: 15
  requires: []
defense:
  hp: 250
  armour: MEDIUM
  frame: MECH
senses:
  vision: vision_ground_medium
movement: {speed: BRISK, turn_rate: 150, max_acceleration: 1.5, max_deceleration: -4.5, min_turn_speed_ratio: 0.5}
weapons:
- name: UnnamedWeapon
  emits:
    id: unnamed_emission
    title: Dunno
    scene: res://scenes/entities/projectiles/lb/dunno.tscn
    damage: 15
    damage_type: LEAD
    speed: HYPER
    trajectory: LINEAR
    hitscan: true
  split_time: 0.333
  reload_time: 0.333
  clip_size: 1
  reach: ground_range_medium
  hits: [ground]
ui: {grid: [3, 1], factions: [libertarian]}
---

TODO the drone augmentation system