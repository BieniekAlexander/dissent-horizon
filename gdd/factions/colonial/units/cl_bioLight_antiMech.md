---
kind: Entity
title: Badger
scene: res://scenes/entities/units/cl/cl_bioLight_antiMech.tscn
build:
  cost:
    energy: 200
  time: 10
  requires: []
defense:
  hp: 100
  armour: LIGHT
  frame: BIO
senses:
  vision: vision_ground_small
  detection: detection_small
movement:
  speed: SLOW
  turn_rate: 1080
  crush_class: TINY
  min_turn_speed_ratio: 0
weapons:
  - name: Weapon
    emits:
      id: badger_rocket
      title: anti-armour rocket
      scene: res://scenes/entities/projectiles/cl/badger_rocket.tscn
      damage: 40
      damage_type: EXPLOSIVE
      hitscan: false
      bio_ground_aim: true
      phases:
        - motion: {preset: LINEAR, speed: BLAZING, jitter: 3}
          lifespan: 2
        - lifespan: 1.6
          payload: once
    split_time: 1.5
    reload_time: 1.5
    clip_size: 1
    reach: ground_range_long
    hits: [ground]
ui:
  grid:
    - 1
    - 1
  factions:
    - colonial
---
## Visuals
- nothing for now
# Notes
- 
