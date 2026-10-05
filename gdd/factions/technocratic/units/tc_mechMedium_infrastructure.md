---
kind: Entity
title: Surveyor
scene: res://scenes/entities/units/an/tc_mechMedium_infrastructure.tscn
flavor:
  description: unarmed vehicle that supplies infrastructure
  verbose: The Technocratic infrastructure provider. Unarmed and carries two light infantry; otherwise it shares the Colonial sloop's properties for now.
build:
  cost:
    energy: 500
  time: 12
  requires: []
defense:
  hp: 300
  armour: MEDIUM
  frame: MECH
senses:
  vision: vision_ground_medium
movement:
  speed: BRISK
  turn_rate: 150
  max_acceleration: 1.5
  max_deceleration: -4.5
  min_turn_speed_ratio: 0.5
garrison:
  capacity: 2
  frames: [BIO]
  armours: [LIGHT]
infrastructure: 75
ui:
  grid: [1, 1]
  factions: [technocracy]
---
