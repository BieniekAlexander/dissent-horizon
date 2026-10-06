---
kind: Entity
title: Servant
scene: res://scenes/entities/units/cl/cl_bioLight_builder.tscn
flavor:
  description: unarmed builder; the only Colonial piece that builds or repairs
  verbose: The Colonial builder. Unarmed, with a Recruit's body — it raises every structure the faction fields, repairs what is damaged, and is what a Compound turns captured prisoners into.
build:
  cost:
    energy: 200
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
  - cl_commandCenter
  - nt_extractor
  - cl_infrastructure
  - cl_barracks
  - cl_defense_antiAircraft
  - cl_defense_antiLight
  - cl_defense_antiStructure
  - cl_airField
  - cl_warFactory
  - cl_tech1
  - cl_tech2
  - cl_support1
  - cl_support2
  - cl_support3
repairs: true
ui:
  grid: [0, 1]
  factions:
    - colonial
---
## Visuals
- nothing for now — the [[cl_bioLight_antiLight|Recruit]] body without the rifle
# Servant

The Colonial builder, trained at the [[cl_commandCenter|Citadel]]. Unarmed, and the
faction's only piece that builds or repairs.

- **Body of a [[cl_bioLight_antiLight|Recruit]]**, minus its weapon and its
  `spotting`: same hp, armour, frame, vision, aggro and chassis
- The [[cl_mechLight_dominionGen|Stock Truck]] used to carry the `builds:` list. It kept the
  cage and the capturing; the Servant took the trowel
- **Rides a [[cl_mechLight_dominionGen|Stock Truck]]** — the only piece that may be ordered into
  one — and is delivered with its cage to a [[cl_infrastructure|Compound]], where it serves a
  sentence for dominion like a prisoner unless it is let out first
