---
kind: Entity
title: nt_radiation_field
scene: res://scenes/entities/projectiles/nt/nt_radiation_field.tscn
flavor:
  description: Scattered activated debris — a field that keeps hurting whatever stands in it.
  verbose: The field a breached activation cask leaves. INCENDIARY for how it scales — full against organics, 0.4 against machines, falling off with armour — so every unit in it is hurt and a strong vehicle shrugs most of it off. It lasts a minute.
damage: 4
damage_type: INCENDIARY
blast: aoe_small
hitscan: false
phases:
  - motion: {preset: LINEAR, speed: ZERO}
    ends_on_arrival: false
    lifespan: 0.25
    visuals: [Vent]
  - lifespan: 60
    payload: 0.5
    visuals: [Field, FieldRing]
---

# nt_radiation_field

The lingering field of a volatile activation cask
([environmental-pieces](../../../systems/combat/environmental-pieces.md)).
