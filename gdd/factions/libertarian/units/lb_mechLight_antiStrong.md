---
kind: Entity
title: Refraction Tank
scene: res://scenes/entities/units/lb/lb_mechLight_antiStrong.tscn
flavor:
    description: Lazer-armed tank, can deploy for stronger defense
    verbose: Lazer-armed tank, can deploy for stronger defense
build:
  cost: {energy: 600}
  time: 15
  requires: []
defense:
  hp: 250
  armour: LIGHT
  frame: MECH
senses:
  vision: vision_ground_medium
movement: {speed: BRISK, turn_rate: 150, max_acceleration: 1.5, max_deceleration: -4.5, min_turn_speed_ratio: 0.5}
weapons:
  - name: LazerWeaponTank
    emits: lazer
    split_time: 1.3333
    reload_time: 1.3333
    clip_size: 1
    reach: ground_range_long
    hits: [ground]
deploys: {time: 3, undeploy_time: 1, cancellable: false}
ui: {grid: [1, 1], factions: [libertarian]}
---
Deploys like every deploying unit ([deploying](../../../systems/commands/deploying.md)): 3 s to plant, 1 s to pack up, and not cancellable. Deployed, its armour steps up one class (LIGHT → MEDIUM).

TODO: what deploying gains this unit is a placeholder — the armour step stands in until a per-unit bonus is chosen, keeping to the rule that the deployed bonus never matches a true static's efficiency per cost ([static-defence](../../../design-framework/static-defence.md) §Libertarians).