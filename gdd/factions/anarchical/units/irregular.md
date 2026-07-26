---
kind: unit
id: irregular
title: irregular
scene: res://scenes/entities/units/an/irregular.tscn
cost: {ore: 75}
build_time: 15
requires: []
hp: 80
armour: LIGHT
frame: BIOLOGICAL
vision: 12
aggro: 5
movement: {mode: GROUNDED_DIRECT, speed: 1.65, turn_rate: 1080}
builds: [stronghold, hangar, field_hospital, safehouse, mine]
weapons:
  - name: BallisticWeapon
    projectile:
      id: irregular_bullet
      scene: res://scenes/entities/projectiles/an/irregular_bullet.tscn
      damage: 5
      damage_type: LEAD
      speed: 1
      trajectory: LINEAR
      hitscan: true
    split_time: 0.3333
    reload_time: 0.3333
    clip_size: 1
    reach: 5
    hits: [ground]
ui: {label: Irregular, grid: [2, 2], factions: [anarchists]}
---

# Irregular

Trained at the [[stronghold|Redoubt]].

- cheap, weak anti-infantry
- Builder
