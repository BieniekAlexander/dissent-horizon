---
kind: Entity
title: sleeper
scene: res://scenes/entities/units/cl/cl_bioLight_stealth.tscn
flavor:
  description: potato
  verbose: potato
build:
  cost:
    energy: 450
  time: 15
  requires:
    - cl_tech1
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
  min_turn_speed_ratio: 0
weapons:
  - name: Shotgun
    emits:
      id: sleeper_shell
      title: shotgun blast
      damage: 45
      damage_type: LEAD
      blast: aoe_small
      speed: SUPERSONIC
      trajectory: LINEAR
      hitscan: false
    split_time: 0.3
    reload_time: 3
    clip_size: 2
    reach: ground_range_medium
    hits:
      - ground
abilities:
  - max_charges: 1
    cooldown: 15
    grants:
      - spot
stealth: true
plants_beacons: true
flushes: true
ui:
  grid:
    - 3
    - 1
  factions:
    - colonial
---
## Visuals
- Maybe a copy of the irregular model, but with a trangular torso instead of a rectangular one
# Notes
- `stealth: true` gives the piece a `Stealth` component. Presence is the whole mechanic — the component has no exports; what REVEALS it is another piece's `detection:` radius.
- **A shotgun**: two LEAD shells 0.5 s apart, then a 5 s reload, at `ground_range_medium`
  (Alex, 2026-10-09). Each shell bursts over `aoe_small` for 30, so it is an ambush burst on
  clustered infantry rather than a mainline gun — and, like every blast, it hits friends in
  the pattern. Not hitscan: a hitscan emission carries no blast shape
  ([projectiles](../../../systems/combat/projectiles.md) §The shape's presence is the blast).
  Clip size and damage per shell were Alex's picks; the cadence is from his spec.
- **Storms garrisons** (`flushes: true`; Alex, 2026-10-10). Right-clicked onto a flushable
  garrison its enemy holds, it walks up, kills everything inside and takes the place itself, in
  one tick. See [garrison-and-transport](../../../systems/combat/garrison-and-transport.md)
  §Flushing a garrison.
- **Plants beacons only after [[cell_activation|Cell Activation]]** is researched at the
  [[cl_tech1|Operations Center]]. Until then its Spot button stays on the card, drawn LOCKED.
- **Plants beacons** with the same [[spot|Spot]] order a Recruit uses, in its own way
  (`plants_beacons: true`): it walks to the point itself, takes 3 seconds to plant, and
  leaves the ground beacon a Beacon Drop places — then moves on, free. The beacon stands
  until a Bombard spends it or an enemy repairs it away, and calls no automatic fire. The
  15 s cooldown runs from the plant. See
  [bombardment](../../../systems/combat/bombardment.md) §Planting a beacon.
