---
kind: Entity
title: Stronghold
scene: res://scenes/entities/structures/an/an_commandCenter.tscn
build:
  cost:
    energy: 1500
  time: 30
  requires: []
defense:
  hp: 2500
  armour: STRONG
  frame: MECH
senses:
  vision: vision_ground_large
footprint:
  - 4
  - 4
trains:
  - an_bioMedium_dominionGen
  - an_bioLight_builder
abilities:
  - max_charges: 1
    initial_charges: 0
    cooldown: 60
    grants:
      - dignify
      - informant
infrastructure: 100
ui:
  grid:
    - 1
    - 0
  context_grid:
    - 0
    - 0
  factions:
    - anarchists
---
