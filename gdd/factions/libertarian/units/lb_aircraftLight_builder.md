---
kind: Entity
title: Canary
scene: res://scenes/entities/units/lb/lb_aircraftLight_builder.tscn
flavor:
    description: Libertarian builder unit, able to fly
    verbose: Libertarian builder unit, able to fly
build:
  cost: {energy: 200}
  time: 12
  requires: []
defense:
  hp: 100
  armour: LIGHT
  frame: MECH
senses:
  vision: vision_aerial_large
movement: {speed: QUICK, turn_rate: 180, max_acceleration: 2, max_deceleration: -3, reverse_speed_ratio: 0.35}
aerial: {mode: HOVERING}
docking: true
builds: [nt_extractor, lb_commandCenter, lb_infrastructure, lb_dominion, lb_barracks, lb_warFactory, lb_airField]
ui: {grid: [0, 1], factions: [libertarian]}
---
