---
kind: Entity
title: nt_cryo_burst
scene: res://scenes/entities/projectiles/nt/nt_cryo_burst.tscn
flavor:
  description: A ruptured dewar's cold cloud — a small burst, and a freeze on every unit in it.
  verbose: The burst a volatile cryo dewar throws where it died. A quarter-second of venting is the fuse; the cloud then freezes the units standing in it and leaves structures alone.
damage: 20
damage_type: PLASMA
blast: aoe_small
status_effects: [cryo_burst]
hitscan: false
phases:
  - motion: {preset: LINEAR, speed: ZERO}
    ends_on_arrival: false
    lifespan: 0.25
    visuals: [Vent]
  - lifespan: 2
    payload: once
    visuals: [Cloud, FieldRing]
---

# nt_cryo_burst

The burst of a volatile cryo dewar
([environmental-pieces](../../../systems/combat/environmental-pieces.md)).
