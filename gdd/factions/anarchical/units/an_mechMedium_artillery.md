---
kind: Entity
title: MLRS
scene: res://scenes/entities/units/an/an_mechMedium_artillery.tscn
flavor:
  description: potato
  verbose: potato
build:
  cost: {energy: 750}
  time: 15
  requires: [an_tech1]
defense:
  hp: 220
  armour: MEDIUM
  frame: MECH
senses:
  vision: vision_ground_medium
movement:
  speed: STEADY
  turn_rate: 90
  max_acceleration: 0.75
  max_deceleration: -2.25
  crush_class: MEDIUM
  min_turn_speed_ratio: 0.3
weapons:
  - name: RocketPod
    emits:
      id: mlrs_rocket
      title: artillery rocket
      scene: res://scenes/entities/projectiles/an/mlrs_rocket.tscn
      damage: 20
      damage_type: EXPLOSIVE
      blast: aoe_small
      hitscan: false
      bio_ground_aim: true
      phases:
        - motion: {preset: LOFTED, launch_pitch: 45, gravity: 18.75, speed: BLAZING, jitter: 3}
        - lifespan: 1.6
          payload: once
    split_time: 0.1
    reload_time: 10
    startup_time: 1
    clip_size: 12
    reach: ground_range_siege
    hits: [ground, air]
ui: {grid: [3, 1], factions: [anarchists]}
exceptions:
  reach_within_vision: artillery requiring spotting
---
# Notes
- Twelve rockets 0.1s apart, then a 10s reload: the salvo-then-vulnerable rhythm the spec
  asked for. `reload_time` is the time for a FULL clip, so the doc's 10s is exactly the
  gap between salvos
- NOT `charged:` — it reloads on its own in the field. A charged clip would send it back
  to a structure between salvos, which is the airfield mechanic and wrong for a ground gun
- `blast: aoe_small` per rocket, EXPLOSIVE (0.75 vs LIGHT, 1.0 vs MEDIUM, 0.6 vs STRONG), so the
  salvo shreds massed light/medium and friendly units in the pattern are hit
- `reach: ground_range_siege` is what makes it artillery. There is no minimum range. Its
  vision (`vision_ground_medium`) is shorter than that reach (radii:
  [shapes.md](../../../shapes/shapes.md)), so past its own sight it fires only on what
  spotters show it — hence the `reach_within_vision` exception
- `startup_time: 1` — a second of holding a target before the first rocket, kept through the
  reload, so a battery that keeps its target salvoes every 10s but one that switches pays
  again ([weapon-cadence](../../../systems/combat/weapon-cadence.md) §Attack startup)
- `hits: [ground, air]` at the ground reach (one `reach:` id covers both layers). TODO: a lob
  aimed where an aircraft WAS lands short of anything that moved — whether anti-air MLRS
  fire should be a different, faster flight is open; see weapon-cadence.md §The MLRS
- The rocket is LOFTED at 45° under 18.75 u/s² rather than the roster's 4.5: the steeper
  gravity keeps the full-reach flight at ~1.6s, what the old flat BALLISTIC arc took at
  BLAZING, with a ~6u apex. At 4.5 the same lob would take ~3.3s. `speed: BLAZING` is only the
  fallback for a target too high for the pitch (an aircraft close overhead). The rocket
  scene is the MLRS's alone, so no copy was needed to change its flight
