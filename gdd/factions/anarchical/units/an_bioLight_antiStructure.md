---
kind: Entity
title: Sapper
scene: res://scenes/entities/units/an/an_bioLight_antiStructure.tscn
flavor:
  description: potato
  verbose: potato
build:
  cost: {energy: 500}
  time: 20
defense:
  hp: 90
  armour: LIGHT
  frame: BIO
senses:
  vision: vision_ground_small
  detection: detection_small
movement: {speed: SLOW, turn_rate: 1080, min_turn_speed_ratio: 0}
abilities:
  - max_charges: 1
    cooldown: 30
    grants:
      - plant
repairs: true
ui: {grid: [0, 1], factions: [anarchists]}
---
