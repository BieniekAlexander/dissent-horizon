---
kind: Entity
title: Matilda
scene: res://scenes/entities/units/cl/cl_mechMedium_antiMech.tscn
flavor:
  description: Fragile but mobile tank, good against mechs
  verbose: Fragile but mobile tank, good against mechs
build:
  cost:
    energy: 600
  time: 15
  requires: []
defense:
  hp: 400
  armour: MEDIUM
  frame: MECH
senses:
  vision: vision_ground_medium
movement:
  speed: BRISK
  turn_rate: 150
  max_acceleration: 1.5
  max_deceleration: -4.5
  crush_class: MEDIUM
  min_turn_speed_ratio: 0.5
weapons:
  - name: BallisticWeapon
    emits:
      id: carronade_shell
      title: siege shell
      scene: res://scenes/entities/projectiles/cl/carronade_shell.tscn
      damage: 90
      damage_type: SIEGE
      speed: SUPERSONIC
      trajectory: LINEAR
      hitscan: true
    split_time: 2
    reload_time: 2
    clip_size: 1
    turret: true
    turret_turn_rate: 360
    reach: ground_range_long
    hits:
      - ground
ui:
  grid:
    - 1
    - 1
  factions:
    - colonial
---
# Matilda
- [Matilda](https://en.wikipedia.org/wiki/Matilda_II), an "infantry tank"
