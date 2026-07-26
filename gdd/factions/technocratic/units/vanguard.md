---
kind: unit
id: vanguard
title: vanguard
scene: res://scenes/entities/units/tc/vanguard.tscn
cost: {ore: 200}
build_time: 20
requires: []
hp: 12000
armour: LIGHT
frame: BIOLOGICAL
vision: 5
aggro: 2
movement: {mode: GROUNDED_DIRECT, speed: 1.2}
weapons:
  - name: LazerWeapon
    projectile: lazer
    split_time: 1.3333
    reload_time: 1.3333
    clip_size: 1
    reach: 15
    hits: [ground]
ui: {label: Vanguard, grid: [3, 2], factions: [technocracy]}
---

# Vanguard
