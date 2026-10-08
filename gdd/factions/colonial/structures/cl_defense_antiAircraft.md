---
kind: Entity
title: Sam
scene: res://scenes/entities/structures/cl/cl_defense_antiAircraft.tscn
flavor:
  description: potato
  verbose: potato
build:
  cost:
    energy: 400
  time: 15
  requires:
    - cl_infrastructure
defense:
  hp: 500
  armour: MEDIUM
  frame: MECH
senses:
  vision: vision_ground_medium
footprint:
  - 1
  - 1
weapons:
  - name: MissileLauncher
    emits:
      id: sam_missile
      title: anti-air missile
      scene: res://scenes/entities/projectiles/cl/sam_missile.tscn
      damage: 40
      damage_type: EXPLOSIVE
      hitscan: false
      bio_ground_aim: true
      phases:
        - motion: {preset: HOMING, speed: SCORCHING, turn_rate: 180, acceleration: 20, jitter: 4}
          lifespan: 5
        - lifespan: 1.6
          payload: once
    split_time: 0.5
    reload_time: 3
    clip_size: 3
    reach: ground_range_artillery
    hits:
      - air
infrastructure: -50
ui:
  grid:
    - 3
    - 0
  factions:
    - colonial
---
