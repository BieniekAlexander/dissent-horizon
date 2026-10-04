---
kind: Entity
title: Condor
scene: res://scenes/entities/units/an/an_aircraftMedium_support.tscn
build:
  cost: {energy: 1200}
  time: 30
  requires: [an_tech2]
defense:
  hp: 220
  armour: MEDIUM
  frame: MECH
senses:
  vision: vision_aerial_medium
movement: {speed: SWIFT, turn_rate: 140, max_acceleration: 2.33, max_deceleration: -1.16}
aerial: {mode: FLYING}
docking: true
weapons:
  - name: EmpBomb
    emits:
      id: condor_emp_bomb
      title: EMP bomb
      scene: res://scenes/entities/projectiles/an/condor_emp_bomb.tscn
      damage: 10
      damage_type: ELECTRIC
      blast: aoe_medium
      status_effects: [emp]
      speed: HYPER
      trajectory: BALLISTIC
      hitscan: false
    split_time: 1
    reload_time: 8
    clip_size: 1
    charged: true
    reach: ground_range_medium
    hits: [ground]
ui: {grid: [2, 1], factions: [anarchists]}
---
# Notes
- One bomb, then it is dry: `charged: true` means the clip never refills in the field, so
  the Condor flies home to an [[an_airField|air field]], parks on a pad and takes
  `reload_time` (8s) to rearm. Being FLYING it commits to a long shallow approach rather
  than sinking onto the pad. One sortie = one EMP, which is what makes the ability worth
  a 350-energy airframe rather than a spammable stun
- **The area is `blast: aoe_medium`**, and that one shape governs BOTH halves:
  `Projectile._apply_hit` resolves the entities its hit shape overlaps once, then damages
  that set and seeds its `EffectApplicator` with the same set. So everything within 3
  units takes the (small) ELECTRIC hit AND is EMP'd — they cannot desynchronise
- Friendly units in the radius are included; the blast query is `TARGETABLE_ANY`
- `emp` is a MECH-only stun (see [[emp]]); BIO infantry caught in the blast take the
  damage and shrug off the stun. That is the unit's role — it answers armour, not crowds
- Damage is deliberately token (10). The Condor is a disabler; killing is someone else's
  job while the target cannot move or shoot
