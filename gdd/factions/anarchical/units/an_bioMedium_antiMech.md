---
kind: Entity
title: Shock Trooper
scene: res://scenes/entities/units/an/an_bioMedium_antiMech.tscn
flavor:
  description: potato
  verbose: potato
build:
  cost: {energy: 400}
  time: 20
defense:
  hp: 90
  armour: MEDIUM
  frame: BIO
senses:
  vision: vision_ground_small
  detection: detection_small
movement: {speed: SLOW, turn_rate: 1080, min_turn_speed_ratio: 0}
weapons:
  - name: ArcWeapon
    emits:
      id: shock_trooper_arc
      title: shock arc
      scene: res://scenes/entities/projectiles/an/shock_trooper_arc.tscn
      damage: 12
      damage_type: ELECTRIC
      status_effects: [emp]
      speed: SUPERSONIC
      trajectory: LINEAR
      hitscan: true
    split_time: 1
    reload_time: 1
    clip_size: 1
    reach: ground_range_medium
    hits: [ground]
ui: {grid: [1, 1], factions: [anarchists]}
---
# Notes
- The cheap end of the same idea as the Juggernaut: ELECTRIC damage plus a MECH-only stun
  (see [[emp]]). 125 energy, so a squad of them locks armour down by weight of fire
- Single target (`hitscan: true`). Stacking EMPs from several troopers refreshes the stun
  rather than extending it — `StatusEffect` re-application is a fresh instance per hit
- `repairs: true` dropped here too; it was the Sapper template showing through
