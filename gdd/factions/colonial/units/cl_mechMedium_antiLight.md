---
kind: Entity
title: sloop
scene: res://scenes/entities/units/cl/cl_mechMedium_antiLight.tscn
flavor:
  description: Convoy escort vehicle, good against lightly armored targets and aircrafts
  verbose: Convoy escort vehicle, good against lightly armored targets and aircrafts
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
weapons:
  - name: BallisticWeapon
    emits:
      id: sloop_bullet
      title: autocannon round
      scene: res://scenes/entities/projectiles/cl/sloop_bullet.tscn
      damage: 22.5
      damage_type: LEAD
      speed: SUPERSONIC
      trajectory: LINEAR
      hitscan: true
    split_time: 0.1333
    reload_time: 1.8
    clip_size: 10
    reach: {ground: ground_range_long, air: air_range_siege}
    hits: [ground, air]
garrison:
  capacity: 6
  frames: [BIO]
  armours: [LIGHT]
ui:
  grid:
    - 0
    - 1
  factions:
    - colonial
---
# Sloop
- named after [Sloop of War](https://en.wikipedia.org/wiki/Sloop-of-war), a "convoy defense vehicle"
- Weapon began as a hard copy of the retired petrel's, with air targeting added
- **A 10-round autocannon burst** of 22.5 each, 0.1333s (4 ticks) apart, then 1.8s to reload: a
  3s cycle holding the 75 DPS it had, with twice the Recruit's alpha-to-DPS ratio. The split is
  what makes it overkill less up close: a round fired within ~3.7u lands before the next leaves.
  See [weapon-cadence](../../../systems/combat/weapon-cadence.md) §Framing: LEAD weapons
- `garrison: {capacity: 2, frames: [BIO], armours: [LIGHT]}` — light infantry only. The capacity of 2 was a guess when the component was hand-added and is still unspecified.
