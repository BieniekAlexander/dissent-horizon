---
kind: Entity
title: Watch Tower
scene: res://scenes/entities/structures/cl/cl_defense_antiLight.tscn
flavor:
  description: Lookout post that guns down infantry, detects stealth and spots for Bombards
  verbose: Lookout post. Its machine gun shreds lightly armoured infantry, it detects stealthed units, and the ground around it is spotted for your Bombards.
build:
  cost:
    energy: 400
  time: 30
  requires:
    - cl_infrastructure
defense:
  hp: 500
  armour: MEDIUM
  frame: MECH
senses:
  vision: vision_ground_large
  detection: detection_medium
footprint:
  - 1
  - 1
weapons:
  - name: BallisticWeapon
    emits:
      id: watch_tower_bullet
      title: tower machine-gun round
      scene: res://scenes/entities/projectiles/cl/watch_tower_bullet.tscn
      damage: 25
      damage_type: LEAD
      speed: SUPERSONIC
      trajectory: LINEAR
      hitscan: true
    split_time: 0.1
    reload_time: 3.0
    clip_size: 6
    reach: ground_range_long
    hits:
      - ground
beacon: 12
infrastructure: -50
ui:
  grid:
    - 3
    - 1
  factions:
    - colonial
---

# Watch Tower

Colonial static defence against light infantry, and the faction's low-tech detector. Its place
in the faction's coverage, and why it is built ahead of a threat rather than in reaction to one:
[[static-defence]].

- **LEAD, ground only.** 1.0 against bio-light; 0.4 against light mechs and 0.24 against medium
  mechs, so against the Warden it is mostly a detector and a spotter.
- **Reach** is `ground_range_long`, out-ranging the Recruit's `ground_range_medium` and staying
  below the artillery classes (static-defence invariant 3).
- **Detection** is `detection_medium` — the Colonial answer to invariant 6.
- **Spots for the Bombard.** `beacon: 12` is a `BeaconRange`: a Bombard may fire into anywhere
  within 12 of the tower without spending a beacon. See [[bombardment]].
- **Alpha strike** — statics carry a high alpha (Decided 2026-10-02). The gun is the 6 × 25
  burst from [[static-defence]] §Alpha strike: 150 damage in 0.5 s, then a 3 s reload, which
  holds against up to four Badgers where the old 4 × 15 gun held two.
- TODO calibrate: every number above is a first pass modelled on the SAM — cost, the long build
  time (structures are meant to build slowly so forward placement is expensive), the gun, and the
  spotting radius, which should stay at or below the tower's vision.
