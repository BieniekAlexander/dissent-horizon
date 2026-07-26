---
kind: unit
id: badger
title: badger
scene: res://scenes/entities/units/cl/badger.tscn
cost: {ore: 200}
build_time: 25
requires: []
hp: 100
armour: LIGHT
frame: BIOLOGICAL
vision: 5
aggro: 2
movement: {mode: GROUNDED_DIRECT, speed: 1.5, turn_rate: 1080}
weapons:
  - name: Weapon
    projectile:
      id: badger_rocket
      scene: res://scenes/entities/projectiles/cl/badger_rocket.tscn
      damage: 15
      damage_type: EXPLOSIVE
      speed: 0.3
      trajectory: LINEAR
      hitscan: false
    split_time: 1.5
    reload_time: 1.5
    clip_size: 1
    reach: 5
    hits: [ground]
ui: {label: Badger, grid: [2, 2], factions: [collective]}
---

# Badger

Trained at the [[barracks|Barracks]].

- Basic anti-armor unit, long range rockets
