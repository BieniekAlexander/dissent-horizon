---
kind: Upgrade
title: Rapid Rearmament
flavor:
  description: Drakes rearm twice as fast on the pad.
build:
  cost: {energy: 500}
  time: 30
ui: {grid: [1, 2], factions: [colonial]}
modifies:
  - piece: cl_aircraftMedium_antiMech
    rearm_rate_factor: 2.0
---
# Rapid Rearmament

Researched at the [[cl_tech1|Operations Center]]. A [[cl_aircraftMedium_antiMech|Drake]] docked
at a Sky Port refills its rockets twice as fast: 100% faster, so its 20-second rearm takes 10.
It stacks with whatever the bay's own charge rate is.

**Price:** 500 energy (Alex, 2026-10-06). The 30-second research time is a placeholder.

How upgrades work in general: [upgrades](../../../systems/macroeconomics/upgrades.md).
