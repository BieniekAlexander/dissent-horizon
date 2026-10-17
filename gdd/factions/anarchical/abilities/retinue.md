---
kind: AbilityDefinition
title: Retinue
flavor:
  description: Friendly infantry standing with this Warlord bank dominion every cycle.
  verbose: |
    A POSITIONAL passive, like the Colonials' [[work_detail|Work Detail]] and unlike anything
    that is fired: it is on for as long as the Warlord is alive, and what it is worth depends
    entirely on where the Warlord is standing.

    Every friendly BIO unit inside its reach pays dominion once a cycle. The Warlord itself
    does not count, and neither does a second Warlord — this is a claim on FOLLOWERS, so a
    pile of Warlords with nobody to lead banks nothing.

    A unit standing in two Warlords' reaches is counted ONCE. Stacking Warlords on one squad
    is not a strategy; spreading them across the squads you already field is.
passive: true
reveals: DOMINION
valence: BOON
---
# Retinue

The Anarchical dominion route, and the mirror of the Colonial one: where the Colonials
CAPTURE bodies and bank them in a [[cl_infrastructure|Compound]], the Anarchists claim
dominion by having their infantry follow somebody.

## Mechanic
Every `AnarchicalDominion.TICK_RATE` ticks, each Warlord sweeps its own `DominionRegion`
collider for friendly BIO units and pays `dominion_per_unit` for each. The sweep is run once
per COMMANDER rather than once per Warlord, because the de-duplication is the mechanic: a
unit in two reaches is one follower.

## Why it is an ability rather than a piece id
The sweep used to name `an_bioMedium_dominionGen` outright, which made "is this a dominion
aura source" a fact about one piece rather than a capability. It now asks whether a piece
GRANTS this ability, so a second such unit — an upgraded Warlord, another faction's answer to
the same idea — needs a doc and no code.

It is also what puts the aura in the info panel and lets the player see its reach: a passive
ability draws a card ([hud-layout](../../../systems/ux/ui/hud-layout.md) §The info rows), and
hovering that card paints the collider it names ([range-reveal](../../../systems/ux/ui/range-reveal.md)).
