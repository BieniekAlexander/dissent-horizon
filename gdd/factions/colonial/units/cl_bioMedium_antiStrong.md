---
kind: Entity
title: Constable
scene: res://scenes/entities/units/cl/cl_bioMedium_antiStrong.tscn
flavor:
  description: Armed peacekeeper
  verbose: Medium bio unit trained at the Barracks
build:
  cost:
    energy: 500
  time: 12
  requires:
    - cl_tech2
defense:
  hp: 225
  armour: MEDIUM
  frame: BIO
senses:
  vision: vision_ground_small
  detection: detection_small
movement:
  speed: SLOW
  turn_rate: 1080
  min_turn_speed_ratio: 0
weapons:
  - name: BallisticWeapon
    emits:
      id: constable_bullet
      title: carbine round
      scene: res://scenes/entities/projectiles/cl/constable_bullet.tscn
      damage: 65
      damage_type: PLASMA
      hitscan: true
      phases:
        - motion: {preset: LINEAR, speed: SUPERSONIC}
        - lifespan: 0.5
          payload: once
    split_time: 0.1
    reload_time: 1.0
    clip_size: 2
    reach: {ground: ground_range_medium, air: air_range_long}
    hits:
      - ground
      - air
ui:
  grid:
    - 2
    - 1
  factions:
    - colonial
---
## Visuals
- Just use a recruit model, and give it an additional flat cube on top of its head, as a hat
# Notes
- **Tuned against the Sloop, one-on-one in a stand-up fight** (2026-10-06): both in range from
  the start, it wins with ~22% hp at 3.3 s. 65 PLASMA ×0.75 vs the Sloop's MEDIUM MECH is 48.75
  a round, so the Sloop's 300 takes 7 rounds — two-round bursts on a 1.1 s cycle. The Sloop's
  first 10-round burst (13.5 a round vs MEDIUM BIO, 135 in all) lands whole, and the kill comes
  after the third round of its second burst, which starts at 3.0 s.
- **The cadence is part of that tuning, not only the damage.** The Sloop's damage arrives in
  bursts, so the hp left is set by WHEN the kill lands against them: before 3.0 s it keeps 40%,
  just inside the second burst ~20%. A 3-round clip could only land its kill on the same tick as
  a Sloop round, making the result depend on which shot the engine resolves first.
- **It loses if it has to walk in under fire:** the Sloop reaches 12 to its 8 and is BRISK to
  its SLOW, so closing the gap costs a full burst before it fires. Range is the Sloop's counter. 