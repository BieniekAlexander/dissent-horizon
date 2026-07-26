---
kind: structure
id: cannon
title: cannon
scene: res://scenes/entities/structures/cl/cannon.tscn
hp: 500
armour: HEAVY
frame: METALLIC
vision: 10
aggro: 9
footprint: [3, 3]
weapons:
  - name: HeavyCannon
    projectile:
      id: cannon_shell
      scene: res://scenes/entities/projectiles/cl/cannon_shell.tscn
      damage: 50
      damage_type: ELECTRIC
      speed: 0.3
      trajectory: BALLISTIC
      hitscan: false
    split_time: 5
    reload_time: 5
    clip_size: 1
    reach: 10
    hits: [ground]
---

# Cannon
