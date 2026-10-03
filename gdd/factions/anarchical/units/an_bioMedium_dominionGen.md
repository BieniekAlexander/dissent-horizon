---
kind: Entity
title: Warlord
scene: res://scenes/entities/units/an/an_bioMedium_dominionGen.tscn
flavor:
  description: dominion-claiming infantry unit, effective against armored targets
  verbose: dominion-claiming infantry unit, armed with a rocket launcher. Effective against armored units, and weak against infantry. Acquire dominion by staying close to allied infantry units.
build:
  cost: {energy: 250}
  time: 8
  requires: []
defense:
  hp: 160
  armour: MEDIUM
  frame: BIO
senses:
  vision: vision_ground_small
  detection: detection_small
movement: {speed: SLOW, turn_rate: 1080, crush_class: SMALL, min_turn_speed_ratio: 0}
weapons:
  - name: Weapon
    emits:
      id: warlord_rocket
      title: Warlord rocket
      scene: res://scenes/entities/projectiles/an/warlord_rocket.tscn
      damage: 40
      damage_type: EXPLOSIVE
      hitscan: false
      bio_ground_aim: true
      phases:
        # Slower than the Badger's rocket and longer-lived, because it must also catch
        # aircraft: QUICK aircraft and every ground class cannot escape it, a FAST aircraft
        # fired on from beyond ~9.5 can (gdd/systems/combat/projectiles.md §Rocket calibration).
        - motion: {preset: HOMING, speed: RAPID, turn_rate: 120, jitter: 4}
          lifespan: 5
        - lifespan: 1.6
          payload: once
    split_time: 1.5
    reload_time: 1.5
    clip_size: 1
    reach: {ground: ground_range_long, air: air_range_long}
    hits: [ground, air]
abilities:
  - max_charges: 1
    cooldown: 1
    grants: [retinue]
ui: {grid: [0, 1], factions: [anarchists]}
---

