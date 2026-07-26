---
kind: unit
id: technician
title: technician
scene: res://scenes/entities/units/an/technician.tscn
cost: {ore: 100}
build_time: 25
requires: []
hp: 100
armour: LIGHT
frame: BIOLOGICAL
vision: 5
aggro: 2
movement: {mode: HOVERING, speed: 3.6, turn_rate: 100}
builds: [dwelling, lab, compound, armory, stronghold, field_hospital, safehouse]
weapons:
  - name: MeleeWeapon
    melee_damage: 10
    melee_damage_type: LEAD
    split_time: 0.3333
    reload_time: 0.3333
    clip_size: 1
    reach: 0.375
    hits: [ground]
ui: {label: Techie, grid: [1, 2], factions: [anarchists]}
---

# Technician
