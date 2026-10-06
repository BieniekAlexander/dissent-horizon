---
kind: Upgrade
title: Reinforced Hulls
flavor:
  description: Sloops and Matildas take a quarter more punishment.
build:
  cost: {energy: 700}
  time: 40
ui: {grid: [2, 2], factions: [colonial]}
modifies:
  - piece: cl_mechMedium_antiLight
    hp_factor: 1.25
  - piece: cl_mechMedium_antiMech
    hp_factor: 1.25
---
# Reinforced Hulls

Researched at the [[cl_tech1|Operations Center]]. The [[cl_mechMedium_antiLight|Sloop]] and the
[[cl_mechMedium_antiMech|Matilda]] get 25% more hit points. A unit already on the field keeps its
fraction of health under the higher maximum.

**Price:** 700 energy (Alex, 2026-10-06). The 40-second research time is a placeholder.

How upgrades work in general: [upgrades](../../../systems/macroeconomics/upgrades.md).
