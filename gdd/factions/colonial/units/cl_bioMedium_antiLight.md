---
kind: Entity
title: Constable
scene: res://scenes/entities/units/cl/cl_bioMedium_antiLight.tscn
flavor:
  description: Armed peacekeeper
  verbose: Medium bio unit trained at the Barracks
build:
  cost:
    energy: 200
  time: 12
  requires:
    - cl_tech1
defense:
  hp: 150
  armour: MEDIUM
  frame: BIO
senses:
  vision: vision_ground_small
  detection: detection_small
movement:
  speed: SLOW
  turn_rate: 1080
  min_turn_speed_ratio: 0
weapons:
  - name: BallisticWeapon
    emits:
      id: constable_bullet
      title: carbine round
      scene: res://scenes/entities/projectiles/cl/constable_bullet.tscn
      damage: 8
      damage_type: LEAD
      speed: SUPERSONIC
      trajectory: LINEAR
      hitscan: true
    split_time: 0.3
    reload_time: 0.3
    clip_size: 1
    reach: {ground: ground_range_medium, air: air_range_long}
    hits:
      - ground
      - air
ui:
  grid:
    - 2
    - 1
  factions:
    - colonial
---
## Visuals
- Just use a recruit model, and give it an additional flat cube on top of its head, as a hat
# Notes
- 