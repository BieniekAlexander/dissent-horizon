---
kind: Entity
title: Irregular
scene: res://scenes/entities/units/an/an_bioLight_builder.tscn
flavor:
  description: Guerilla fighter that builds structures, effective in numbers
  verbose: Guerilla fighter armed with a light rifle. Cheap and strong in numbers, effective against other infantry. Can also build structures.
build:
  cost: {energy: 100}
  time: 8
  requires: []
defense:
  hp: 80
  armour: LIGHT
  frame: BIO
senses:
  vision: vision_ground_small
  detection: detection_small
body:
  radius: .2
  target: .2
movement: {speed: SLOW, turn_rate: 1080, crush_class: TINY, min_turn_speed_ratio: 0}
weapons:
- name: BallisticWeapon
  emits:
    id: irregular_bullet
    title: rifle round
    scene: res://scenes/entities/projectiles/an/irregular_bullet.tscn
    damage: 5
    damage_type: LEAD
    speed: SUPERSONIC
    trajectory: LINEAR
    hitscan: true
  split_time: 0.1
  reload_time: 0.8
  clip_size: 3
  reach: ground_range_medium
  hits: [ground]
builds: [nt_extractor, an_commandCenter, an_airField, an_infrastructure, an_barracks, an_warFactory, an_support1, an_support2, an_support3, an_tech1, an_tech2]
ui: {grid: [1, 1], factions: [anarchists]}
---
# Notes
- **A 3-round rifle burst**, 0.1s apart, then 0.8s to reload: the same 15 DPS as a single shot
  every third of a second, delivered in bursts with a short window between them — the canonical
  early-game rifle. See [weapon-cadence](../../../systems/combat/weapon-cadence.md) §Framing:
  LEAD weapons
