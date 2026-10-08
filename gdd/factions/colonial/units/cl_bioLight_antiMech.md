---
kind: Entity
title: Badger
scene: res://scenes/entities/units/cl/cl_bioLight_antiMech.tscn
flavor:
  description: potato
  verbose: potato
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
        # Slow ignition, boost, then coast, steering throughout: faster than every ground
        # class in play, so none escapes it; only a vehicle about as fast as a slow aircraft
        # (FAST or above, none yet) can (gdd/systems/combat/projectiles.md §Rocket calibration).
        - motion:
            speed: SCORCHING
            turn_rate: 60
            launch_speed_ratio: 0.1212   # leaves the tube at ~2 u/s
            acceleration: 40             # up to SCORCHING in ~0.36 s
            min_speed: 2
            jitter: 3
            burn: 0.5
            coast_speed: SWIFT
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
