---
kind: Entity
title: Gunship
scene: res://scenes/entities/units/cl/cl_aircraftMedium_gunship.tscn
editor_description: Off-map gunship flown by the Gunship sanction. Takes Attack orders on station; never Move.
flavor:
  description: Called-in gunship. Holds station over a point for a while, firing on anything below.
  verbose: |
    Not a piece anyone builds. It answers a Gunship sanction: it flies in from your side of
    the board with its guns cold, circles the point you called it to, and fires on whatever
    it finds there until its time on station runs out. Then it goes home the way it came.

    It takes Attack orders while on station, but it will not leave its station to go
    anywhere else — and it can be shot down.
defense:
  hp: 600
  armour: MEDIUM
  frame: MECH
senses:
  vision: vision_aerial_medium
movement: {speed: HYPER, turn_rate: 150, max_acceleration: 6, max_deceleration: -10}
aerial: {mode: FLYING, orbit_speed: FLEET}
weapons:
  - name: BallisticWeapon
    emits:
      id: gunship_bullet
      title: gunship autocannon round
      scene: res://scenes/entities/projectiles/cl/gunship_bullet.tscn
      damage: 67.5
      damage_type: LEAD
      speed: SUPERSONIC
      trajectory: LINEAR
      hitscan: true
    split_time: 0.1333
    reload_time: 1.8
    clip_size: 10
    turret: true
    range_from: orbit
    reach: {ground: ground_range_long, air: air_range_long}
    hits: [ground, air]
---

# Gunship

The aircraft the [Gunship](../sanctions/gunship.md) sanction sends. See
[Off-map abilities](../../../systems/macroeconomics/sanctions/off-map-abilities.md) §Gunship
for the sortie it flies.

## Notes
- **The weapon is the Sloop's at triple damage** (22.5 → 67.5): the split, reload and clip
  are a hard copy. It differs in the round's damage, in being a `turret` (a circling aircraft
  rarely points its nose at what it shoots), and in its reach: 12 on both layers
  (`ground_range_long`, `air_range_long`; Alex, 2026-10-06). Its own emission
  (`gunship_bullet`) rather than the Sloop's, so retuning one never moves the other.
- **It fights from its orbit** (`range_from: orbit`): it is meant as an aircraft firing out of
  one side while it circles a point, at anything inside the circle it flies. So its reach is
  the range shape standing at the orbit's centre, a target in reach stays in reach all the way
  round, changing target never moves it — and its orbit radius is not authored: the importer
  sets it to the weapon's ground reach.
- **HP, armour and handling are placeholders** (Alex, 2026-10-06: "pretty arbitrarily filled
  in for now"), to be tuned once it has been flown in a game. Orbit speed FLEET is Alex's.
- No `ui:` key — never built or trained, so it has no command-grid button and its economy
  figures are the importer's placeholder defaults.
- No `docking:` — it never lands, and has no airfield to rearm at; the clip reloads in the air.
