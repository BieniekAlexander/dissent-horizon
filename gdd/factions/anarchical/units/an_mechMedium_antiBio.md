---
kind: Entity
title: Toxin Tractor
scene: res://scenes/entities/units/an/an_mechMedium_antiBio.tscn
flavor:
  description: potato
  verbose: potato
build:
  cost: {energy: 600}
  time: 15
defense:
  hp: 220
  armour: MEDIUM
  frame: MECH
senses:
  vision: vision_ground_medium
movement:
  speed: BRISK
  turn_rate: 150
  max_acceleration: 1.5
  max_deceleration: -4.5
  crush_class: MEDIUM
  min_turn_speed_ratio: 0.5
weapons:
  - name: ToxinSprayer
    emits:
      id: toxin_cloud
      title: toxin cloud
      scene: res://scenes/entities/projectiles/an/toxin_cloud.tscn
      damage: 18
      damage_type: TOXIC
      blast: aoe_medium
      speed: HYPER
      trajectory: LINEAR
      hitscan: false
      flushes: true
    split_time: 1
    reload_time: 1
    clip_size: 1
    reach: ground_range_medium
    hits: [ground]
ui: {grid: [1, 1], factions: [anarchists]}
---
# Notes
- TOXIC is the anti-BIO damage type — 1.0 vs BIO, 0.15 vs MECH in the damage table — so
  the id's `antiBio` role is carried by the damage type alone, with no status effect
  needed. Against vehicles it is nearly inert, by design
- `blast: aoe_medium` makes it an area weapon: a sprayer that hit one soldier at a time would be
  a worse rifle. Friendly infantry in the cloud are hit too
- NOT a damage-over-time. A lingering toxin cloud would be a `DamageOverTimeStatusEffect`
  (the script exists — `lazer_burn` uses it) and is the obvious next step if this wants
  to read as gas rather than as a caustic shell
- **It flushes garrisons** (`flushes: true` on the cloud; Alex, 2026-10-10): a cloud that STRIKES
  a flushable garrison's host kills everything inside. Only a direct hit counts — catching the
  building in the blast does not. See
  [garrison-and-transport](../../../systems/combat/garrison-and-transport.md) §Flushing a garrison
