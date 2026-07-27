---
kind: Entity
title: Technician
scene: res://scenes/entities/units/an/tc_bioLight_builder.tscn
build:
  cost: {energy: 100}
  time: 25
  requires: []
defense:
  hp: 100
  armour: LIGHT
  frame: BIO
senses:
  vision: vision_ground_small
  detection: detection_small
movement: {speed: SLUGGISH, turn_rate: 1080, min_turn_speed_ratio: 0}
builds: [] # [tc_dominion, tc_commandCenter, nt_extractor, tc_tech1]
garrison: {}
ui: {grid: [0, 1], factions: [technocracy]}
---

