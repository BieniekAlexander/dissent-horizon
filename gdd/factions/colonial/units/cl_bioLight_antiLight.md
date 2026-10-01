---
kind: Entity
title: Recruit
scene: res://scenes/entities/units/cl/cl_bioLight_antiLight.tscn
build:
  cost:
    energy: 100
  time: 8
  requires: []
defense:
  hp: 120
  armour: LIGHT
  frame: BIO
senses:
  vision: vision_ground_small
  detection: detection_small
movement:
  speed: SLOW
  turn_rate: 1080
  crush_class: TINY
  min_turn_speed_ratio: 0
weapons:
  - name: BallisticWeapon
    emits:
      id: recruit_bullet
      title: service rifle round
      scene: res://scenes/entities/projectiles/cl/recruit_bullet.tscn
      damage: 7.5
      damage_type: LEAD
      speed: SUPERSONIC
      trajectory: LINEAR
      hitscan: true
    split_time: 0.1333
    reload_time: 1.2333
    clip_size: 3
    reach: ground_range_medium
    hits:
      - ground
abilities:
  - max_charges: 3
    cooldown: 3
    grants:
      - irradiate
  - max_charges: 1
    cooldown: 1
    grants:
      - spot
ui:
  grid:
    - 0
    - 1
  factions:
    - colonial
---
## Visuals
- nothing for now
# Notes
- Carries the Colonial artillery's forward-observer half, granted as the [[spot|Spot]]
  ability: it walks to within 10 units of a chosen point, holds still for 10 seconds, and
  leaves a beacon standing there for the Bombards to spend. It stays on that beacon until
  the shot lands — see the Spot command. Those two numbers are `Spot.TARGET_RANGE` and
  `Spot.CHANNEL_TICKS`, not doc keys: this is the only piece in the game that spots, so they
  never vary. They become a `spotting:` mapping on the day a second, longer-ranged spotter
  exists.
- `antiLight` is the role vocabulary's "good against light targets generally" — light mech and light bio alike — as against Badger's `antiArmor`, which is mech-only at any armour weight
- **A 3-round rifle burst**, 0.1333s (4 ticks) apart, then 1.2333s to reload: a 1.5s cycle at
  the same 15 DPS it had. See [weapon-cadence](../../../systems/combat/weapon-cadence.md)
  §Framing: LEAD weapons
