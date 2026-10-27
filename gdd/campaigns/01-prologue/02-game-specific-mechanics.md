# Mission 2 — Game-specific mechanics

Status: draft, not built. Reworked 2026-10-27 to apply [mission-design](../mission-design.md), the
lessons of building mission 1. The design intent is unchanged. The player holds a defunct
Anarchist base against Colonial raids while banking dominion. The dominion unlocks two
sanctions: Informant, to slip units through for critical strikes, and Mortar Strike, for the
firepower to finish the mission.

## Teaches

- **Unit abilities:** the [Sapper](../../factions/anarchical/units/an_bioLight_antiStructure.md)'s [Plant](../../factions/anarchical/abilities/plant.md) and [Detonate](../../factions/anarchical/abilities/detonate.md). These cover arming an ability, choosing its target, and reading its charge and cooldown. A planted charge holds the Sapper's recharge until it goes off. Detonate fires from anywhere, with or without vision of the charge.
- **Crushing:** vehicles run over clumped infantry, and spread-out infantry survives and kills the vehicle. The player's infantry is the main target, and the player crushes too.
- **Stealth:** stealthed units move unseen until they attack, and detectors reveal them.
- **Dominion generation:** the Anarchist route, [Retinue](../../factions/anarchical/abilities/retinue.md). Friendly infantry standing with a Warlord bank dominion.
- **Ordnances:** buying a sanction with dominion, then casting it from the structure that holds its charge, with a cooldown before the next charge. This reuses the charge-and-cooldown vocabulary the Sapper introduced, moved from a unit to a structure.
- **Garrison clearing:** flushing Colonial infantry out of buildings.

## Reinforces

From mission 1: unit control, garrisoning, counters, the Watch Tower warning, and freeing
captives from a Compound by setting off the hazards against it.

## Player fantasy

A ragged cell outnumbered by an industrial army wins through its following, not its factories.

## Narrative justification

The base is defunct, so there is no production. What the Anarchists still have is people: Warlords and the infantry who follow them, which is what dominion is for this faction. The base's Distress Signals still work if dominion authorises a call, so the base can't win alone but can call in the strikes that do.

## Setup

Numbers are illustration; the scene will hold the real values.

- **Commanders:**
  - **Player** — Anarchical.
  - **Enemy** — a Colonial bot, **scripted only** (every bot job that acts switched off): its
    raids, patrols and garrisons are all authored.
  - No ally. The player's own base is the anchor, so no guide is needed to make the route
    legible until the strikes (open question Q3).
- **Starting base**, placed in the scene:
  - A [Stronghold](../../factions/anarchical/structures/an_commandCenter.md), which casts Informant. The base needs one for this reason.
  - One or more [Distress Signals](../../factions/anarchical/structures/an_support2.md), which cast Mortar Strike
  - Neutral buildings to garrison
  - No production. TODO: there is no scenario-level way to switch off training at the
    Stronghold yet (README §Impact of mission 1's build).
- **Starting force**, placed in the scene:
  - [Warlords](../../factions/anarchical/units/an_bioMedium_dominionGen.md) and infantry
  - A [Toxin Tractor](../../factions/anarchical/units/an_mechMedium_antiBio.md) for garrison clearing. It's a vehicle, so it also gives the player something to crush with.
- **Received during the mission:** [Sappers](../../factions/anarchical/units/an_bioLight_antiStructure.md),
  arriving as reinforcements before the critical strikes. They spawn relative to the base, from
  off the map (`spawn_in_flight` or a ground arrival), out of the raiders' reach.
- **Sanction grid:** only Informant and Mortar Strike are offered. Other cells are hidden or
  locked. TODO: needs a scenario-level sanction restriction, which doesn't exist yet.
- **Enemies:**
  - **Raids on the base**, one lesson each, in a fixed order: a lone
    [Stock Truck](../../factions/colonial/units/cl_mechLight_dominionGen.md) that captures a
    light infantryman, then a [Sloop](../../factions/colonial/units/cl_mechMedium_antiLight.md)
    driving at a clump, then mixed raids with [Matildas](../../factions/colonial/units/cl_mechMedium_antiMech.md).
    A raid is set off by a beat or by the previous raid being spent, never by a repeating timer,
    and never while the previous raid lives. Raids stop once the strikes begin, or thin out,
    so the player can leave the base.
  - **A Colonial prison for the captured:** the Stock Truck delivers its captive to a Compound
    with hazards against it, as in mission 1, so the player can win the captive back
    (open question Q2).
  - [Watch Towers](../../factions/colonial/structures/cl_defense_antiLight.md) as the detectors guarding the strike targets, each defending group sharing one defended area
  - Colonial infantry garrisoned in buildings on the route out, placed in the scene

## The tension the mission is built on

Retinue rewards infantry standing together around a Warlord, and crushing punishes infantry standing together. The player has to bank dominion without presenting a clump to the Colonial vehicles. That's done by spreading followers across several Warlords, which is also how Retinue rewards play. Defending the base and earning dominion become the same activity.

## Objectives

One strict `ObjectiveChain` that reads the beats below. A beat finished early ticks its
objective off when it is shown.

1. **Hold the base through the first raids** while banking dominion.
2. **Buy [Informant](../../factions/anarchical/sanctions/informant.md).**
3. **Destroy the strike targets without being detected.** Sub-steps, one per target. The
   targets are marked and revealed. The route past the Watch Towers' detection is unmarked:
   finding it is the objective.
4. **Buy [Mortar Strike](../../factions/anarchical/sanctions/mortar.md) and destroy the final
   objective with it.**

Failure conditions (proposed, Q1): **the Stronghold must survive** (it casts Informant), **at
least one Distress Signal must survive** (it casts Mortar Strike), and **at least one Warlord
must survive** (without one no dominion is banked). A sheltering Warlord counts.

**What the player is shown.** Marked: the raiders while a raid is on; the Sappers' arrival
point; the strike targets; the final objective. Reveals: each strike target while objective 3 is
current, and the final objective once Mortar Strike is bought. None for the stealth route.

**Autosaves** (proposed): when the first raids are held, when Informant is bought, and before
the final strike.

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

Help notes: one topic each, raised by the trigger named, teaching what the next objective
needs. "New" notes are to be written for the How to Play library, since the main campaigns
will need them too.

| Introduced by | Notes, in order |
|---|---|
| Mission start | Dominion (new, Retinue); Selecting a group (reused) |
| First Stock Truck sighted | Captured units (new: the Stock Truck, the prison, freeing captives) |
| Sloop sighted | Crushing (new) |
| Toxin Tractor's first crush, or a beat after the Sloop raid | Crushing with your own vehicles (new, or folded into Crushing) |
| Objective 1 done | Sanctions and ordnances (new) |
| Sappers arrive | Abilities (new: arm, target, charge, cooldown); Holding a charge (new) |
| Objective 2 done (Informant bought) | Stealth and detection (new) |
| First Watch Tower sighted | the Watch Tower warning, already shown in mission 1 (Q4) |
| First garrisoned Colonial building sighted | Clearing garrisons (new) |
| Objective 3 done | Ordnance delivery: where the shells come from (new) |

## Constraints

- No production or construction. The base is defunct.
- Only two sanctions in the grid.
- No commander-wide upgrades.
- No aircraft on either side, and no spotting-dependent pieces.
- No mechanic before it is explained. Check every placed and spawned piece against this,
  including the reinforcements: the Toxin Tractor's crush comes after the Crushing note.

## Scenario file

TODO — link once it exists under `scenes/scenarios/prologue/`. Draw the topology first and
import it through the map generator's image mode ([mission-design](../mission-design.md)
§Building the map).

## Open questions

**Q1. Failure conditions.** Mission 1 fails when the player loses every unit, or every Warlord
once captives are free. Should mission 2 fail when the Stronghold, the last Distress Signal or
the last Warlord is lost, since each makes it unwinnable?
*Leaning:* all three, each as a `FAILURE` row.

**Q2. Winning captives back.** Should a captured infantryman go to a Compound the player can
blow open, as in mission 1, or just be lost?
*Why it matters:* reusing the prison gives the Stock Truck a stake the player already
understands, and a reason to counterattack. It also gives the player a way to undo the raid.
*Leaning:* a prison, but only for the first capture, as a callback.

**Q3. A guide for the strikes.** Mission 1's guide squad made each next goal legible. The
strikes leave the base for unknown ground. Should a stealthed ally (an informant) lead the
first strike, or are the marks and reveals enough?
*Leaning:* marks and reveals. Route-finding is part of the stealth lesson.

**Q4. The Watch Tower warning is a mission-1-only note** (`scenes/dialogs/prologue_m1/`). It is
needed here too, and in mission 3.
1. Move it into the How to Play library.
2. Keep a copy per mission.

*Leaning:* 1. A note two missions use isn't mission-specific.

**Engine work (decided).** Two scenario features are needed before this mission can be built:
a sanction-grid restriction per commander, and switching off production (or training at the
Stronghold). Mission 3 needs the same family (a tech cap and excluded pieces). Both are to be
built, scoped on their own, apart from the challenges' input conditions, which belong to a
different system (Alex, 2026-10-27).
