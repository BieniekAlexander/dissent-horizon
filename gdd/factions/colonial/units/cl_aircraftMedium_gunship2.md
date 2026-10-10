---
kind: Entity
title: Gunship 2
scene: res://scenes/entities/units/cl/cl_aircraftMedium_gunship2.tscn
editor_description: Off-map gunship flown by the Gunship 2 sanction. Takes Attack orders on station; never Move.
flavor:
  description: Called-in gunship. Holds station over a point for a while, firing on anything below.
  verbose: |
    Not a piece anyone builds. It answers a Gunship 2 sanction: it flies in from your side of
    the board with its guns cold, circles the point you called it to, and fires on whatever
    it finds there until its time on station runs out. Then it goes home the way it came.

    It takes Attack orders while on station, but it will not leave its station to go
    anywhere else — and it can be shot down.
defense:
  hp: 600
  armour: MEDIUM
  frame: MECH
senses:
  vision: vision_ground_small
  vision_from: orbit
movement: {speed: HYPER, turn_rate: 150, max_acceleration: 6, max_deceleration: -10}
aerial: {mode: FLYING, orbit_speed: FLEET}
weapons:
  - name: BallisticWeapon
    emits:
      id: gunship2_bullet
      title: gunship carbine round
      scene: res://scenes/entities/projectiles/cl/gunship2_bullet.tscn
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
    turret: true
    range_from: orbit
    reach: {ground: ground_range_long, air: air_range_long}
    hits: [ground, air]
---

# Gunship 2

The aircraft the [Gunship](../sanctions/gunship.md) sanction sends at level 2. Everything but
the weapon is a copy of [[cl_aircraftMedium_gunship]].

## Notes
- **The weapon is a placeholder hard copy of the Constable's** ([[cl_bioMedium_antiStrong]];
  Alex, 2026-10-10, "for now"): the round, split, reload and clip are copied, under its own
  emission (`gunship2_bullet`) so retuning one never moves the other. It keeps the two keys
  that mount any weapon on this airframe, `turret` and `range_from: orbit`.
- **Its reach is level 1's, not the Constable's** (Alex, 2026-10-10): `ground_range_long` and
  `air_range_long`, so it flies the same orbit as [[cl_aircraftMedium_gunship]] — the importer
  sets the orbit radius to the weapon's ground reach.
- The hull, handling, orbit speed and orbit-centred vision are level 1's; retune both docs
  together.
