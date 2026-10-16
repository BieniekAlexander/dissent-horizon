---
kind: Entity
title: nt_plasma_blast_large
scene: res://scenes/entities/projectiles/nt/nt_plasma_blast_large.tscn
flavor:
  description: A storage cell's quench — a plasma burst that burns what it touches.
  verbose: The blast a volatile battery bank throws where it died. Its first phase is the FUSE — a quarter-second of venting before it goes — and the payout lands once, lighting every structure in it.
damage: 600
damage_type: PLASMA
blast: aoe_large
status_effects: [burning]
hitscan: false
phases:
  - motion: {preset: LINEAR, speed: ZERO}
    ends_on_arrival: false
    lifespan: 0.25
    visuals: [Vent]
  - lifespan: 2.4
    payload: once
    visuals: [Burst]
---

# nt_plasma_blast_large

The blast of a volatile battery bank
([environmental-pieces](../../../systems/combat/environmental-pieces.md)). The first phase's
lifespan is the fuse.
