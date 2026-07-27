---
kind: Entity
title: Vanguard
scene: res://scenes/entities/units/tc/tc_bioLight_antiMech.tscn
build:
  cost: {energy: 200}
  time: 20
  requires: []
defense:
  hp: 12000
  armour: LIGHT
  frame: BIO
senses:
  vision: vision_ground_small
  detection: detection_small
movement: {speed: SLUGGISH, turn_rate: 1080, min_turn_speed_ratio: 0}
weapons:
  - name: LazerWeapon
    emits: lazer
    split_time: 1.3333
    reload_time: 1.3333
    clip_size: 1
    reach: ground_range_siege
    hits: [ground]
garrison: {}
abilities:
  - max_charges: 3
    cooldown: 3
    grants: [irradiate]
ui: {grid: [0, 1], factions: [technocracy]}
exceptions:
  reach_within_vision: >-
    Stand-off lazer infantry: fires on ground the rest of the squad is holding. `ground_range_siege` against `vision_ground_small` — revisit when the Technocracy is balanced.
---

# Vanguard
