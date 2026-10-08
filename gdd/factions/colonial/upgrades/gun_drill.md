---
kind: Upgrade
title: Gun Drill
flavor:
  description: Bombard crews reload in two thirds the time.
  verbose: potato
build:
  cost: {energy: 1000}
  time: 50
ui: {grid: [1, 2], factions: [colonial]}
modifies:
  - piece: cl_defense_antiStructure
    ability: bombard
    cooldown_rate_factor: 1.5
---
# Gun Drill

Researched at the [[cl_tech2|Academy]]. Every [[cl_defense_antiStructure|Bombard]]'s charge
recharges half again as fast, cutting a third off its cooldown: 30 seconds become 20 (Alex,
2026-10-06).

**Price:** 1000 energy (Alex, 2026-10-06). The 50-second research time is a placeholder.

How upgrades work in general: [upgrades](../../../systems/macroeconomics/upgrades.md).
