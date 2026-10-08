---
kind: Entity
title: Juggernaut
scene: res://scenes/entities/units/an/an_bioStrong_antiLight.tscn
flavor:
  description: potato
  verbose: potato
build:
  cost: {energy: 1000}
  time: 20
  requires: [an_tech1]
defense:
  hp: 90
  armour: STRONG
  frame: BIO
senses:
  vision: vision_ground_small
  detection: detection_small
movement: {speed: SLOW, turn_rate: 1080, min_turn_speed_ratio: 0}
weapons:
  - name: BallisticWeapon
    emits:
      id: juggernaut_bullet
      title: heavy rifle round
      scene: res://scenes/entities/projectiles/an/juggernaut_bullet.tscn
      damage: 12
      damage_type: LEAD
      speed: SUPERSONIC
      trajectory: LINEAR
      hitscan: true
    split_time: 0.4
    reload_time: 0.4
    clip_size: 1
    reach: {ground: ground_range_medium, air: air_range_long}
    hits: [ground, air]
ui: {grid: [3, 1], factions: [anarchists]}
---
# Notes
- TODO: calibrate. It is STRONG with 90 hp and costs 1000, while the note below prices its
  weapon as a 500-energy unit's — none of those three numbers has been set against the others.
- Ballistic autocannon that answers BOTH layers. LEAD is the anti-light damage type (1.0
  vs LIGHT, 0.6 vs MEDIUM, 0.25 vs STRONG; 1.0 vs BIO, 0.4 vs MECH), so the `antiLight`
  role is carried by the damage type alone and no status effect is needed
- `hits: [ground, air]` with a SPLIT reach — medium on the ground, long in the air. The
  longer air bucket follows the Warlord's shape (ground long, air siege): anti-air wants
  reach, because aircraft close the distance far faster than infantry can be walked out of it
- `hitscan: true`, single target. This is a sustained-fire platform, not an area weapon —
  the Toxin Tractor and the MLRS are the Anarchists' AOE
- Numbers are placeholder pending balance: 12 damage on a 0.4s cycle is 30 dps before
  multipliers, roughly double a Recruit's rifle, which is about where a 500-energy `an_tech1`
  unit should sit. Nothing has been balanced against it
- Replaces the retired `an_bioHeavy_superUnit` Juggernaut, whose ELECTRIC/EMP arc went with
  it. `emp` itself survives — the Condor still carries it
- Its doc named `an_bioMedium_antiLight.tscn`, a piece that does not exist; corrected to
  match its own id, as every other new an_* piece does
