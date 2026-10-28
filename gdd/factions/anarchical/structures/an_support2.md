---
kind: Entity
title: Distress Signal
scene: res://scenes/entities/structures/an/an_support2.tscn
flavor:
  description: potato
  verbose: potato
build:
  cost: {energy: 1200}
  time: 30
  requires: [an_tech1]
defense:
  hp: 1500
  armour: MEDIUM
  frame: MECH
senses:
  vision: vision_ground_large
footprint: [3, 3]
abilities:
  - max_charges: 1
    cooldown: 120
    alert: true
    grants: [mortar, ambush]
infrastructure: -100
ui:
  grid: [2,2]
  factions: [anarchists]
---

# Notes
- **One pool for Mortar Strike and Ambush, 120 s** (Alex, 2026-10-27). The Hideout, which cast
  Ambush on its own pool (180 s), was removed and its ability moved here. Casting either spends
  the charge for both. Ambush now needs the Stockpile (this structure's prerequisite) rather
  than the Hideout's Barracks, so it arrives later in a match.
