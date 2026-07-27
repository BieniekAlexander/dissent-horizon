---
kind: Entity
title: avalanche
scene: res://scenes/entities/units/cl/cl_mechStrong_support.tscn
flavor:
  description: Strongly armored support vehicle, capable up locking down armies
  verbose: Strongly armored support vehicle, capable up locking down armies
build:
  cost:
    energy: 1200
  time: 20
  requires:
    - cl_tech2
defense:
  hp: 200
  armour: STRONG
  frame: MECH
senses:
  vision: vision_ground_medium
movement:
  speed: STEADY
  turn_rate: 90
  max_acceleration: 0.75
  max_deceleration: -2.25
  min_turn_speed_ratio: 0.3
weapons:
  - name: CryoWeapon
    emits:
      id: avalanche_shell
      title: cryo shell
      scene: res://scenes/entities/projectiles/cl/avalanche_shell.tscn
      damage: 50
      damage_type: CRYO
      speed: SUPERSONIC
      trajectory: LINEAR
      hitscan: true
    split_time: 2
    reload_time: 2
    clip_size: 1
    reach: ground_range_long
    hits:
      - ground
ui:
  grid:
    - 3
    - 1
  factions:
    - colonial
---
# Notes
- Its own `avalanche_shell` projectile, CRYO damage, ground-only. It used to name
  `carronade_shell` — the Matilda's (`cl_mechMedium_antiMech`) inline projectile — which
  was not sharing but a duplicate id: two docs each declaring an inline projectile of the
  same name is a hard import error, so nothing colonial imported at all
- Everything but the damage type and the id is carried over from that copy (50 damage,
  hitscan, linear, 3.5 reach, 2s cycle) and is placeholder pending balance
- The "lock down armies" the title promises is not built: CRYO is a damage type here, not
  a slow. The status effect it would apply is the follow-up
