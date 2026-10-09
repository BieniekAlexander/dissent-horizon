---
kind: Upgrade
title: Cell Activation
flavor:
  description: Sleepers can plant beacons for the artillery.
  verbose: potato
build:
  cost: {energy: 500}
  time: 30
ui: {grid: [3, 2], factions: [colonial]}
modifies:
  - piece: cl_bioLight_stealth
    ability: spot
    unlocks: true
---
# Cell Activation

Researched at the [[cl_tech1|Operations Center]]. Until it is, a
[[cl_bioLight_stealth|Sleeper]] cannot plant beacons: it is trained with its [[spot|Spot]] order
on its card, drawn LOCKED, and the order is refused ("Requires research"). Researching it lets
every Sleeper the commander fields plant, those already on the field included. The
[[cl_bioLight_antiLight|Recruit]]'s Spot is untouched.

It is the first upgrade with an `unlocks:` effect: a gate on one piece's use of one ability,
rather than a change to a number.

**Price:** 500 energy (Alex, 2026-10-09). The 30-second research time is a placeholder.

How upgrades work in general: [upgrades](../../../systems/macroeconomics/upgrades.md).
