---
kind: AbilityDefinition
title: Cryogenic Implosion
flavor:
  description: potato
  verbose: potato
ui: {grid: [2, 2], factions: [colonial]}
hud_button: true
column: 2
levels:
  - title: Cryogenic Implosion
    tier: 4
    cost: 300
    cooldown: 60
    description: Frost gathers over the target for 5 seconds, then implodes, dealing 3000 plasma damage to everything inside it.
    verbose: |
      The Colonial superweapon, cast from the {{ cl_support4 }}. The 5 seconds of
      gathering frost are its warning: anyone can see it coming and walk out. When it
      implodes it strikes friend and foe alike, on the ground and in the air.
---
# Cryogenic Implosion

The superweapon tier's Colonial cell. Sits in the Freeze column WITHOUT continuing it, like
Blizzard: it is cast from the Cryogenic Imploder (`cl_support4`), and sharing a column is
layout, not a dependency.

## Mechanic
Places a `cryogenic_implosion_field` at the target point
(`scenes/entities/projectiles/cl/cryogenic_implosion_field.tscn`), through the same
`EventPlaceEmission` Blizzard uses. Three phases, five seconds to the blast:

1. **Gather**, 4.4 s — snowflakes materialise one by one over the `aoe_huge` field and hang
   there; the field's ring marks its edge.
2. **Implode**, 0.6 s — every flake is pulled into the centre, timed to arrive as the phase
   ends (`ImplosionParticles`).
3. **Detonate** — on entering it, 3000 PLASMA damage to every piece inside `aoe_huge`, once.

- **Indiscriminate.** The blast reaches every targetable piece in the volume, the caster's
  own included, and `aoe_huge` is tall enough to reach aircraft.
- **PLASMA is armour-scaled**: 3000 lands in full on LIGHT, ×0.75 on MEDIUM and ×0.6 on
  STRONG, and equally on BIO and MECH.
- **Unattributed.** `EventPlaceEmission` launches with no firing piece, so the blast earns
  no veterancy and pays no kill bounty — the same as Blizzard.
