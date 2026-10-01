---
kind: Upgrade
title: Advanced Targetting
flavor:
  description: Recruits call in firing solutions from much farther away.
build:
  cost: {energy: 800}
  time: 45
ui: {grid: [0, 2], factions: [colonial]}
modifies:
  - piece: cl_bioLight_antiLight
    ability: spot
    range: ground_range_siege
---
# Advanced Targetting

The first upgrade in the game. Researched at the [[cl_tech1|Operations Center]]: the building
that unlocks the [[cl_defense_antiStructure|Bombard]], which is the only thing spotting feeds, so
the upgrade sits where its payoff arrives.

It raises the [[cl_bioLight_antiLight|Recruit]]'s [[spot|Spot]] reach from the ability's own
`range:` to `ground_range_siege`. A spotter can then call a strike in from outside most
structures' vision, and the beacon leash on a unit it has tagged stretches to match. That makes
spotting survivable against a defended target, which is the point: without it, a Recruit has to
walk into the defence it is marking.

**Price (a starting guess, Alex, 2026-09-30):** 800 energy and 45 seconds. That is a little under
a Bombard, because the upgrade pays off only once Bombards exist.

How upgrades work in general: [upgrades](../../../systems/macroeconomics/upgrades.md).
