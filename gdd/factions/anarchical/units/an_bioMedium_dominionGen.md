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
    emits: sam_missile         # shared with the Colonial SAM site for now (cl_defense_antiAircraft)
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

