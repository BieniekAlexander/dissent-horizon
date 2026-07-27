---
kind: Entity
title: Gatling Tank
scene: res://scenes/entities/units/lb/lb_mechLight_antiLight1.tscn
flavor:
  description: Light but mobile gun
  verbose: Light but mobile gun
build:
  cost: {energy: 100}
  time: 10
  requires: []
defense:
  hp: 100
  armour: LIGHT
  frame: MECH
senses:
  vision: vision_ground_medium
movement: {speed: BRISK, turn_rate: 150, max_acceleration: 1.5, max_deceleration: -4.5, min_turn_speed_ratio: 0.5}
weapons:
- name: Gatling
  emits:
    id: gatling_bullet
    title: Gatling Bullet
    scene: res://scenes/entities/projectiles/lb/gatling_bullet.tscn
    damage: 20
    damage_type: LEAD
    speed: HYPER
    trajectory: LINEAR
    hitscan: true
  split_time: 0.333
  reload_time: 0.333
  clip_size: 1
  reach: {ground: ground_range_long, air: air_range_siege}
  hits: [ground, air]
deploys: {time: 3, undeploy_time: 1, cancellable: false}
ui: {grid: [0, 1], factions: [libertarian]}
---
Deploys like every deploying unit ([deploying](../../../systems/commands/deploying.md)): 3 s to plant, 1 s to pack up, and not cancellable. Deployed, its armour steps up one class (LIGHT → MEDIUM).

TODO: what deploying gains this unit is a placeholder — the armour step stands in until a per-unit bonus is chosen, keeping to the rule that the deployed bonus never matches a true static's efficiency per cost ([static-defence](../../../design-framework/static-defence.md) §Libertarians).