---
kind: Entity
title: drake
scene: res://scenes/entities/units/cl/cl_aircraftMedium_antiMech.tscn
flavor:
  description: anti-mech aircraft
  verbose: Well-rounded aircraft with medium armor, good against mechanical targets
build:
  cost:
    energy: 1000
  time: 15
  requires: []
defense:
  hp: 150
  armour: MEDIUM
  frame: MECH
senses:
  vision: vision_aerial_medium
movement:
  speed: FAST
  turn_rate: 90
  max_acceleration: 2
  max_deceleration: -1
aerial:
  mode: FLYING
docking: true
weapons:
  - name: Weapon
    emits:
      id: drake_rocket
      title: aircraft rocket
      scene: res://scenes/entities/projectiles/cl/drake_rocket.tscn
      damage: 35
      damage_type: EXPLOSIVE
      hitscan: false
      bio_ground_aim: true
      phases:
        - motion:
            preset: LINEAR
            speed: HYPER
            jitter: 3
        - lifespan: 1.6
          payload: once
    split_time: 0.1
    reload_time: 20
    clip_size: 4
    charged: true
    reach:
      ground: air_range_long
      air: air_range_long
    hits:
      - ground
      - air
ui:
  grid:
    - 1
    - 1
  factions:
    - colonial
---
# Notes
- `charged: true`: the Drake carries four rockets and cannot reload in the field. It flies
	back to a Sky Port, lands on a pad and takes `reload_time` (20s) to rearm, then resumes
	the order it broke off from.
- Being FLYING rather than HOVERING, it commits to its descent from much further out (see
	`Rearm._approach_radius`) and flies a shallow glide onto the pad instead of sinking onto
	it — a jet has no hover to descend from.
