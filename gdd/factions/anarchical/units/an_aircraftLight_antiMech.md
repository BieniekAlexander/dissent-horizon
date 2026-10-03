---
kind: Entity
title: Kamikaze
scene: res://scenes/entities/units/an/an_aircraftLight_antiMech.tscn
build:
  cost: {energy: 300}
  time: 10
defense:
  hp: 75
  armour: LIGHT
  frame: MECH
senses:
  vision: vision_aerial_medium
movement: {speed: HYPER, turn_rate: 610, max_acceleration: 2, max_deceleration: -1}
aerial: {mode: FLYING}
weapons:
  - name: BombWeapon
    emits:
      id: kamikaze_bomb
      title: suicide charge
      scene: res://scenes/entities/projectiles/an/kamikaze_bomb.tscn
      damage: 150
      damage_type: EXPLOSIVE
      status_effects: [suicide]
      hitscan: false
      phases:
        - motion: {preset: BALLISTIC, speed: FAST}
          lifespan: 0
        - lifespan: 1
          payload: once
    split_time: 0.3333
    reload_time: 0.3333
    clip_size: 1
    reach: {ground: ground_range_melee, air: air_range_melee}
    hits: [ground, air]
abilities:
  - max_charges: 3
    cooldown: 3
    grants: [irradiate]
ui: {grid: [0, 1], factions: [anarchists]}
exceptions:
  aerial_weapons_not_melee: >-
    Kamikaze drone: the attack IS the ram. Its bomb detonates on contact, the airframe is expended, and Movement.dive_turn_rate_multiplier exists so it can actually close.
---

- Like scourge in Brood War
- Should probably do AOE and friendly fire - cool and balanced
- No `docking:` — it spawns airborne and never lands. It has no life to return to: it is
  expended on its first attack run. Not docking also keeps it out of the docking-capacity
  soft gate, so a swarm of drones never reports the air force as short of pads.
  Its bomb is deliberately NOT `charged` — a charged weapon on a unit that cannot dock is
  an import error, since its clip could never be refilled.
- Movement is HYPER, one of the light aircraft that outrun the standard rocket
  ([speed_classes](../../../movement/speed_classes.md)). `turn_radius_within_reach` is
  structural and cannot be waived: at melee reach even its diving turn has to fit a 0.5
  circle. Its turn rate was 160 at FAST and was scaled to 610 with the move to HYPER
  (2026-10-03), so its turning circle, and its dive's, are what they were. Its acceleration
  was NOT scaled (Alex: it took off far too fast): at 2 u/s² it needs about 10 s to reach
  HYPER, so a drone is fast only once it has been flying a while.
