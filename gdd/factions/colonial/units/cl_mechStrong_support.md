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
  speed: SLUGGISH
  turn_rate: 90
  max_acceleration: 0.75
  max_deceleration: -2.25
  min_turn_speed_ratio: 0.3
weapons:
  - name: CryoWeapon
    emits:
      id: avalanche_shell
      title: frost field
      scene: res://scenes/entities/projectiles/cl/avalanche_shell.tscn
      damage: 0
      damage_type: UNDEFINED
      blast: aoe_large
      hitscan: false
      phases:
        - motion: {preset: LINEAR, speed: SUPERSONIC}
        - name: Field
          lifespan: 3
          visuals: [Snowfall, PostImpactMesh, FieldRing]
    split_time: 15
    reload_time: 15
    startup_time: 3
    clip_size: 1
    reach: ground_range_artillery
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
- Its own `avalanche_shell` projectile, ground-only. It used to name
  `carronade_shell` — the Matilda's (`cl_mechMedium_antiMech`) inline projectile — which
  was not sharing but a duplicate id: two docs each declaring an inline projectile of the
  same name is a hard import error, so nothing colonial imported at all
- Its shot deals no damage: after a 3 s startup it stands a 5 s frost field where it lands,
  then reloads for 15 s — see [shields](../../../systems/combat/shields.md) §Frost fields. Its
  type is `UNDEFINED` because a zero-damage shot has none
- It fires on its own like any armed piece; holding fire is how a player keeps it from
  freezing a brawl its own side is in
