---
kind: Entity
title: Lab
scene: res://scenes/entities/structures/tc/tc_dominionGen.tscn
flavor:
  description: gathers dominion; built only on an extraction site
  verbose: The Technocratic dominion route. A Lab is built on an extraction site instead of an Extractor, so every site is a choice between energy and dominion. It gathers dominion only, and cannot work a lithium pond.
build:
  cost: {energy: 500}
  time: 20
  requires: []
defense:
  hp: 500
  armour: MEDIUM
  frame: MECH
senses:
  vision: vision_ground_medium
footprint: [2, 2]
extractor: true
infrastructure: -50
ui: {grid: [2, 0], factions: [technocracy]}
---
