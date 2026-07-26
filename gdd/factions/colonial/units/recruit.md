---
kind: unit
id: recruit
title: recruit
scene: res://scenes/entities/units/cl/recruit.tscn
cost: {ore: 100}
build_time: 20
requires: []
hp: 120
armour: LIGHT
frame: BIOLOGICAL
vision: 12
aggro: 5.75
movement: {mode: GROUNDED_DIRECT, speed: 1.5, turn_rate: 1080}
weapons:
  - name: BallisticWeapon
    projectile:
      id: recruit_bullet
      scene: res://scenes/entities/projectiles/cl/recruit_bullet.tscn
      damage: 7.5
      damage_type: LEAD
      speed: 1
      trajectory: LINEAR
      hitscan: true
    split_time: 0.5
    reload_time: 0.5
    clip_size: 1
    reach: 5.5
    hits: [ground]
ui: {label: Recruit, grid: [1, 2], factions: [collective]}
---

# Recruit

Trained at the [[barracks|Barracks]]. Working design name: **Pathfinder**.

- Basic infantry unit
- Siege spotter
