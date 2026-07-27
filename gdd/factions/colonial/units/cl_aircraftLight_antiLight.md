---
kind: Entity
title: Clipper
scene: res://scenes/entities/units/cl/cl_aircraftLight_antiLight.tscn
flavor:
  description: Light reconnaissance aircraft, good against light armor
  verbose: Light reconnaissance aircraft, good against light armor
build:
  cost:
    energy: 600
  time: 15
  requires: []
defense:
  hp: 120
  armour: LIGHT
  frame: MECH
senses:
  vision: vision_aerial_large
movement:
  speed: QUICK
  turn_rate: 180
  max_acceleration: 2
  max_deceleration: -3
  reverse_speed_ratio: 0.35
aerial: {mode: HOVERING}
docking: true
weapons:
  - name: BallisticWeapon
    emits:
      id: clipper_bullet
      title: strafing round
      scene: res://scenes/entities/projectiles/cl/clipper_bullet.tscn
      damage: 12
      damage_type: LEAD
      speed: SUPERSONIC
      trajectory: LINEAR
      hitscan: true
    split_time: 0.5
    reload_time: 0.5
    clip_size: 1
    charged: false
    reach: ground_range_medium
    hits:
      - ground
ui:
  grid:
    - 0
    - 1
  factions:
    - colonial
---
