---
kind: AbilityDefinition
title: Blizzard
flavor:
  description: potato
  verbose: potato
ui: {grid: [1, 2], factions: [colonial]}
hud_button: true
column: 2
levels:
  - title: Blizzard
    tier: 3
    cost: 1500
    cooldown: 60
    description: A storm gathers over the target for 10 seconds, then freezes every unit that stands in it for 2 seconds, for 10 more.
    verbose: |
      The storm's 10 seconds of gathering are its warning: anyone can see it coming and
      walk out. Once it breaks it freezes friend and foe alike, and holds a frozen unit
      frozen for as long as it stays inside. STRONG armour and structures are not frozen.
---
# Blizzard

Sits in the Freeze column WITHOUT continuing it. It is cast from the Storm Cell
(`cl_support3`) rather than the Operations Center, and sharing a column is layout, not a
dependency — the same relationship Gunship has to the Scan column. Buying Blizzard does
not retire Freeze, and Freeze is not a prerequisite for it.

## Mechanic
Places a `blizzard_field` at the target point: 10 seconds gathering, then a frost field of
`aoe_huge` for 10 seconds. Frost fields and the freeze they apply are
[shields](../../../systems/combat/shields.md) §Frost fields.
