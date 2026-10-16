---
kind: Entity
title: nt_plasma_blast_small
scene: res://scenes/entities/projectiles/nt/nt_plasma_blast_small.tscn
flavor:
  description: A storage cell's quench — a plasma burst that burns what it touches.
  verbose: The blast a volatile power cell throws where it died. Its first phase is the FUSE — a quarter-second of venting before it goes — and the payout lands once, lighting every structure in it.
damage: 150
damage_type: PLASMA
blast: aoe_small
status_effects: [burning]
hitscan: false
phases:
  - motion: {preset: LINEAR, speed: ZERO}
    ends_on_arrival: false
    lifespan: 0.25
    visuals: [Vent]
  - lifespan: 1.8
    payload: once
    visuals: [Burst]
---

# nt_plasma_blast_small

The blast of a volatile power cell
([environmental-pieces](../../../systems/combat/environmental-pieces.md)). The first phase's
lifespan is the fuse.
