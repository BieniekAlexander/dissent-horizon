---
kind: Entity
title: Opticon
scene: res://scenes/entities/structures/lb/lb_dominion.tscn
build:
  cost: {energy: 250}
  time: 15
  requires: [lb_infrastructure]
defense:
  hp: 400
  armour: LIGHT
  frame: MECH
senses:
  vision: vision_ground_medium
footprint: [1, 1]
infrastructure: 500
ui: {grid: [2, 2], factions: [libertarian]}
---
# Opticon

The Libertarian dominion route: spread Opticons across the map rather than packing them into a base.

## Mechanic
Every cycle, each finished Opticon claims the tiles inside its **vision shape** (so retuning its
sight retunes its claim), and every claimed tile banks `dominion_per_tile`. Run once per
commander by `LibertarianDominion`, on the faction scene, rather than once per Opticon:

- **A tile two Opticons both see pays once.** Clustering Opticons wastes their overlap; the
  same de-duplication the Warlord's Retinue uses.
- **A tile under one of your own fixtures pays nothing** — the Opticon itself included. Building
  around an Opticon eats its income, which is what pushes it out of the base. An enemy or
  neutral fixture does NOT shield a tile.
- **Terrain is ignored.** Water, cliffs and other unbuildable tiles pay like open ground.
  TODO: "for now" — whether unbuildable terrain should keep paying is undecided.

PLANNED — ALLIES: "your own fixtures" should become "your side's" once alliances exist.

The bot builds Opticons through this route and spreads them by the same rule — see
[bot-architecture](../../../systems/ai/bot-architecture.md) §Dominion routes. Placing any building shows
the Opticons' claim, pending ones included, and placing an Opticon shows its whole claim with the
tiles that would earn nothing washed out
([construction-visuals](../../../systems/ux/ui/construction-visuals.md) §The placement grid).

TODO: `dominion_per_tile` is a placeholder (a lone Opticon on open ground banks about what a
Warlord with four followers does).

The income is on the economy bar's dominion rate, and what ordered Opticons will add is drawn as
pending ([economy-bars](../../../systems/ux/ui/economy-bars.md) §Dominion). TODO: the Anarchist
route's sweep is not on the bar yet — it answers no rate of its own.
