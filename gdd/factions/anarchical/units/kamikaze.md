---
kind: unit
id: kamikaze
title: kamikaze
scene: res://scenes/entities/units/an/kamikaze.tscn
cost: {ore: 200}
build_time: 25
requires: []
hp: 15
armour: MEDIUM
frame: BIOLOGICAL
vision: 5
aggro: 5
movement: {mode: FLYING, speed: 3, turn_rate: 120}
weapons:
  - name: BombWeapon
    projectile:
      id: kamikaze_bomb
      scene: res://scenes/entities/projectiles/an/kamikaze_bomb.tscn
      damage: 50
      damage_type: EXPLOSIVE
      speed: 0.175
      trajectory: BALLISTIC
      hitscan: false
      status_effects: [suicide]
    split_time: 0.3333
    reload_time: 0.3333
    clip_size: 1
    reach: 0.5
    hits: [ground, air]
ui: {label: Kamikaze, grid: [0, 0], factions: [anarchists]}
---

# Kamikaze Drone

Trained at the [[hangar|Hangar]].

- Like scourge in Brood War
- Should probably do AOE and friendly fire - cool and balanced
