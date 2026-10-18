# Mission 2 — Game-specific mechanics

Status: draft. The player holds a defunct Anarchist base against Colonial raids while banking dominion. The dominion unlocks two sanctions: Informant, to slip units through for critical strikes, and Mortar Strike, for the firepower to finish the mission.

## Teaches

- **Unit abilities:** the [Sapper](../../factions/anarchical/units/an_bioLight_antiStructure.md)'s [Plant](../../factions/anarchical/abilities/plant.md) and [Detonate](../../factions/anarchical/abilities/detonate.md). These cover arming an ability, choosing its target, and reading its charge and cooldown. A planted charge holds the Sapper's recharge until it goes off. Detonate fires from anywhere, with or without vision of the charge.
- **Crushing:** vehicles run over clumped infantry, and spread-out infantry survives and kills the vehicle. The player's infantry is the main target, and the player crushes too.
- **Stealth:** stealthed units move unseen until they attack, and detectors reveal them.
- **Dominion generation:** the Anarchist route, [Retinue](../../factions/anarchical/abilities/retinue.md). Friendly infantry standing with a Warlord bank dominion.
- **Ordnances:** buying a sanction with dominion, then casting it from the structure that holds its charge, with a cooldown before the next charge. This reuses the charge-and-cooldown vocabulary the Sapper introduced, moved from a unit to a structure.
- **Garrison clearing:** flushing Colonial infantry out of buildings.

## Reinforces

Unit control, garrisoning and counters from mission 1.

## Player fantasy

A ragged cell outnumbered by an industrial army wins through its following, not its factories.

## Narrative justification

The base is defunct, so there is no production. What the Anarchists still have is people: Warlords and the infantry who follow them, which is what dominion is for this faction. The base's Distress Signals still work if dominion authorises a call, so the base can't win alone but can call in the strikes that do.

## Setup

- **Starting base:**
  - A [Stronghold](../../factions/anarchical/structures/an_commandCenter.md), which casts Informant. The base needs one for this reason.
  - One or more [Distress Signals](../../factions/anarchical/structures/an_support2.md), which cast Mortar Strike
  - Neutral buildings to garrison
  - No production
- **Starting force:**
  - [Warlords](../../factions/anarchical/units/an_bioMedium_dominionGen.md) and infantry
  - A [Toxin Tractor](../../factions/anarchical/units/an_mechMedium_antiBio.md) for garrison clearing. It's a vehicle, so it also gives the player something to crush with.
- **Received during the mission:** [Sappers](../../factions/anarchical/units/an_bioLight_antiStructure.md), arriving as reinforcements before the critical strikes.
- **Sanction grid:** only Informant and Mortar Strike are offered. Other cells are hidden or locked.
- **Enemies:**
  - Colonial raids on the base: [Stock Trucks](../../factions/colonial/units/cl_mechLight_dominionGen.md) capture light infantry, and [Sloops](../../factions/colonial/units/cl_mechMedium_antiLight.md) and [Matildas](../../factions/colonial/units/cl_mechMedium_antiMech.md) crush them
  - [Watch Towers](../../factions/colonial/structures/cl_defense_antiLight.md) as the detectors guarding the strike targets
  - Colonial infantry garrisoned in buildings on the route out

## The tension the mission is built on

Retinue rewards infantry standing together around a Warlord, and crushing punishes infantry standing together. The player has to bank dominion without presenting a clump to the Colonial vehicles. That's done by spreading followers across several Warlords, which is also how Retinue rewards play. Defending the base and earning dominion become the same activity.

## Objectives

1. Hold the base through the first raids while banking dominion.
2. Buy [Informant](../../factions/anarchical/sanctions/informant.md) and stealth units for the critical strikes.
3. Complete the strikes without being detected.
4. Buy [Mortar Strike](../../factions/anarchical/sanctions/mortar.md) and use it to destroy the final objective.

## Teaching beats

- **Introduce:**
  - Dominion ticks up while infantry stand near a Warlord. Hovering the Retinue card shows its reach.
  - The first raid is a single Stock Truck that captures a lone Irregular. Then a Sloop drives at a clump.
  - Spreading out saves the infantry. The Toxin Tractor runs down an exposed Colonial squad, which shows the player crushing too.
- **Develop:**
  - Sappers arrive.
    - The player plants a charge on a Colonial vehicle or structure and detonates it, which introduces abilities, charges and cooldowns on a single unit.
    - The Sapper can't plant again until its charge goes off, which teaches that a charge can be held.
  - Buy Informant. The ordnance's charge and cooldown show on the Stronghold.
  - Stealthed Irregulars slip past patrols to make the critical strikes.
  - A Watch Tower reveals any unit that strays into its detection range, so routes matter.
- **Twist:** Colonial infantry garrison the buildings on the route. The Toxin Tractor flushes them out, where plain fire wouldn't.
- **Conclude:**
  - Buy Mortar Strike and call it in on the final objective.
  - The shells arrive from the map edge nearest the Distress Signal that called them, so the caster's position matters.

## Constraints

- No production or construction. The base is defunct.
- Only two sanctions in the grid.
- No commander-wide upgrades.

## Scenario file

TODO — link once it exists under `scenes/scenarios/`.

## Open questions

- **Which units go stealthed.** [Informant 1](../../factions/anarchical/sanctions/informant.md) only targets Irregulars, and any BIO unit needs Informant 2. If stealthed Sappers make the critical strikes, the mission needs Informant 2 or a scripted grant.
- **Planting and stealth.** Does planting a charge break a Sapper's stealth, the way attacking does? Detonating from range keeps the Sapper hidden either way. If planting does break stealth, the strikes rely on detonating at a distance.
- **What the critical strikes hit.** Candidates:
  - the Watch Towers themselves, which opens a route
  - the Stock Trucks' Compound, which stops the captures
- **Distress Signal prerequisite.** Distress Signals require a [Stockpile](../../factions/anarchical/structures/an_tech1.md) to build, which doesn't matter for scenario-placed ones. Does the defunct base show the Stockpile as ruined, for consistency?
- **Choosing the caster.** With several Distress Signals, can the player pick which one casts? That decides whether the arrival-edge lesson is something the player can act on.
- **Captured units.** Does a captured Irregular count as a loss, or can it be rescued (e.g. by destroying the Compound)?
