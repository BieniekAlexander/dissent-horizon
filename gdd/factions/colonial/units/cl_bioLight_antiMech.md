---
kind: Entity
title: Badger
scene: res://scenes/entities/units/cl/cl_bioLight_antiMech.tscn
build:
  cost:
    energy: 200
  time: 7
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
        # Slow ignition, boost, then coast, steering throughout: no ground target outruns it
        # from close, and only a QUICK vehicle fired on from beyond ~7 can turn away and
        # escape (gdd/systems/combat/projectiles.md §Rocket calibration).
        - motion:
            speed: BLAZING
            turn_rate: 60
            launch_speed_ratio: 0.1333   # leaves the tube at ~2 u/s
            acceleration: 40             # up to BLAZING in ~0.33 s
            min_speed: 2
            jitter: 3
            burn: 0.5
            coast_speed: RAPID
          lifespan: 2.2
        - lifespan: 1.6
          payload: once
    split_time: 1.5
    reload_time: 1.5
    clip_size: 1
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
## Visuals
- nothing for now
# Notes
- 
