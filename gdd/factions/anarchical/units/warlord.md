---
kind: unit
id: warlord
title: warlord
scene: res://scenes/entities/units/an/warlord.tscn
cost: {ore: 250}
build_time: 20
requires: []
hp: 160
armour: MEDIUM
frame: BIOLOGICAL
vision: 6
aggro: 5
movement: {mode: GROUNDED_DIRECT, speed: 1.2, turn_rate: 1080}
weapons:
  - name: Weapon
    projectile:
      id: warlord_rocket
      scene: res://scenes/entities/projectiles/an/warlord_rocket.tscn
      damage: 25
      damage_type: EXPLOSIVE
      speed: 0.8
      trajectory: HOMING
      hitscan: false
    split_time: 1.5
    reload_time: 1.5
    clip_size: 1
    reach: {ground: 4, air: 10}
    hits: [ground, air]
ui: {label: Warlord, grid: [1, 2], factions: [anarchists]}
---

# Warlord

Trained at the [[stronghold|Redoubt]].

- dominion-generating unit, based on veterancy
- Has a rocket launcher
