---
kind: Entity
title: Technician
scene: res://scenes/entities/units/an/tc_bioLight_builder.tscn
flavor:
  description: unarmed builder; raises every Technocratic structure and repairs what is damaged
  verbose: The Technocratic builder. Unarmed; its faction-agnostic properties match the Colonial Servant's for now.
build:
  cost:
    energy: 500
  time: 8
  requires: []
defense:
  hp: 120
  armour: LIGHT
  frame: BIO
senses:
  vision: vision_ground_small
  detection: detection_small
body:
  radius: 0.2
movement:
  speed: SLUGGISH
  turn_rate: 1080
  crush_class: TINY
  min_turn_speed_ratio: 0
builds:
  - tc_commandCenter
  - nt_extractor
  - tc_dominionGen
garrison: false # parity with the Servant, which carries no garrison
repairs: true
ui:
  grid: [0, 1]
  factions: [technocracy]
---
