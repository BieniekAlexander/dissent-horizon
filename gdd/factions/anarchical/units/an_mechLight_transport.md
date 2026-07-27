---
kind: Entity
title: Collective
scene: res://scenes/entities/units/an/an_mechLight_transport.tscn
build:
  cost: {energy: 400}
  time: 10
  requires: []
defense:
  hp: 220
  armour: LIGHT
  frame: MECH
senses:
  vision: vision_ground_medium
movement:
  speed: QUICK
  turn_rate: 180
  max_acceleration: 3
  max_deceleration: -6
  crush_class: MEDIUM
  min_turn_speed_ratio: 1
garrison: {bunker: false, capacity: 3, frames: [BIO]}
ui: {grid: [0, 1], factions: [anarchists]}
---
TODO give this an upgrade such that it heals nearby BIO units. Just call it "Bio Heal" in the data for now. Note that I had previously implemented a "Field Hospital" unit, labeled `an_support1`, which had this heal ability by default, but I'm removing that unit from the game (note that `an_support1` will now be the identifier for something else), so this unit can now take the implementation from the Field Hospital.