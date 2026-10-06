---
kind: Upgrade
title: Field Conditioning
flavor:
  description: Every BIO unit takes a quarter more punishment.
build:
  cost: {energy: 700}
  time: 40
ui: {grid: [0, 2], factions: [colonial]}
modifies:
  - frame: BIO
    hp_factor: 1.25
---
# Field Conditioning

Researched at the [[cl_tech2|Academy]]. Every BIO unit the commander fields gets 25% more hit
points: the Recruit, Badger, Servant, Sleeper and Constable today, and any BIO unit added or
captured later. Structures are not units and are untouched. A unit already on the field keeps its
fraction of health under the higher maximum.

**Price:** 700 energy (Alex, 2026-10-06). The 40-second research time is a placeholder.

How upgrades work in general: [upgrades](../../../systems/macroeconomics/upgrades.md).
