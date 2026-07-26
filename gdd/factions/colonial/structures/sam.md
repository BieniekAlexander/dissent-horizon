---
kind: structure
id: sam
title: sam
scene: res://scenes/entities/structures/cl/sam.tscn
hp: 500
armour: MEDIUM
frame: METALLIC
vision: 10
aggro: 9
footprint: [1, 1]
weapons:
  - name: MissileLauncher
    projectile:
      id: sam_missile
      scene: res://scenes/entities/projectiles/cl/sam_missile.tscn
      damage: 15
      damage_type: LEAD
      speed: 0.175
      trajectory: HOMING
      hitscan: false
    split_time: 0.5
    reload_time: 3
    clip_size: 3
    reach: 10
    hits: [air]
---

# Sam
