---
kind: Entity
title: War Wagon
scene: res://scenes/entities/units/an/an_mechStrong_transport.tscn
flavor:
  description: potato
  verbose: potato
build:
  cost: {energy: 750}
  time: 20
  requires: [an_tech1]
defense:
  hp: 220
  armour: STRONG
  frame: MECH
senses:
  vision: vision_ground_medium
movement:
  speed: STEADY
  turn_rate: 90
  max_acceleration: 0.75
  max_deceleration: -2.25
  crush_class: MEDIUM
  min_turn_speed_ratio: 0.3
garrison: {bunker: true}
occupancy_size: 2
ui: {grid: [2, 1], factions: [anarchists]}
---
