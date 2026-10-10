---
kind: Entity
title: Cryogenic Imploder
scene: res://scenes/entities/structures/cl/cl_support4.tscn
flavor:
  description: potato
  verbose: potato
build:
  cost: {energy: 2500}
  time: 40
  requires: [cl_tech2]
defense:
  hp: 1500
  armour: STRONG
  frame: MECH
senses:
  vision: vision_ground_large
footprint: [5, 5]
abilities:
  - max_charges: 1
    initial_charges: 0
    cooldown: 180
    alert: true
    grants: [cryogenic_implosion]
infrastructure: -200
ui: {grid: [5, 2], factions: [colonial]}
---
# Cryogenic Imploder

The Colonial superweapon: the one building that casts [[cryogenic_implosion|Cryogenic
Implosion]], and only once the tier-5 sanction is bought.

TODO: every number above (2500 energy, 40 s, 1500 HP, a 300 s charge, -200 infrastructure)
is a placeholder copied up from the Storm Cell (`cl_support3`) and the EMP Device, not a
tuned value — see [structure-costs](../../../systems/macroeconomics/pacing/structure-costs.md).
