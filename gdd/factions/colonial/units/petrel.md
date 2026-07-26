---
kind: unit
id: petrel
title: petrel
scene: res://scenes/entities/units/cl/petrel.tscn
hp: 200
armour: LIGHT
frame: METALLIC
vision: 15
aggro: 2
movement: {mode: HOVERING, speed: 4, turn_rate: 200}
weapons:
  - name: BallisticWeapon
    projectile:
      id: carronade_shell
      scene: res://scenes/entities/projectiles/cl/carronade_shell.tscn
      damage: 75
      damage_type: SIEGE
      speed: 1
      trajectory: LINEAR
      hitscan: true
    split_time: .2
    reload_time: .2
    clip_size: 1
    reach: 7.5
    hits: [ground]
---

# Petrel
