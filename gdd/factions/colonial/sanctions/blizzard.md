---
kind: AbilityDefinition
title: Blizzard
ui: {grid: [1, 2], factions: [colonial]}
hud_button: true
column: 2
levels:
  - title: Blizzard
    tier: 4
    cost: 500
    cooldown: 60
    description: 'Freezes everything in a wide area. STUB: no payload built yet.'
    verbose: 'Not implemented. The cell is real — it costs dominion and runs its cooldown — but firing it does nothing yet.'
---
# Blizzard

Sits in the Freeze column WITHOUT continuing it. It is cast from the Storm Cell
(`cl_support3`) rather than the Operations Center, and sharing a column is layout, not a
dependency — the same relationship Gunship has to the Scan column. Buying Blizzard does
not retire Freeze, and Freeze is not a prerequisite for it.

## Mechanic
**Stubbed.** The area version of Freeze; see `freeze.md` for the rules a cryogenic freeze
follows.
