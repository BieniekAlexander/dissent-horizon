# Mission 3 — Macroeconomics

Status: draft, not built. Reworked 2026-10-27 to apply [mission-design](../mission-design.md) and
to account for what mission 1 now teaches ([README](README.md) §Impact of mission 1's build). A
straightforward assault: build a base and an army, and destroy a Colonial base. Each part of
the enemy base calls for a different tool, which is what motivates producing structures,
climbing the tech tree and using ground transports.

## Teaches

- **Structure production:** builders, placement, build times, and the Safehouse. Anarchist infrastructure comes from occupying neutral buildings, not from a power plant.
- **Infrastructure, from the player's side:** mission 1 taught cutting the enemy's. Here the
  player's own structures go defective when its Safehouses fall short.
- **Unit production:** training from production structures, and rally points.
- **Resource collection:** extractors on extraction sites, which are slow and never deplete, versus lithium ponds, which pay fast and run out.
- **The tech tree:** prerequisites, and that a higher tier unlocks the units for parts of the base the starting roster can't crack.
- **Ground transports:** carrying infantry across ground they can't survive on foot. Air
  transport is mission 1's.
- **Garrison clearing:** flushing Colonial infantry out of buildings, with the
  [Toxin Tractor](../../factions/anarchical/units/an_mechMedium_antiBio.md), in the barracks
  quarter. Moved from mission 2 (Alex, 2026-10-27).
- **Shared ability pools:** the Stronghold's abilities share one pool of charges, so casting
  one spends the other's (Alex, 2026-10-27). TODO: the Stronghold's pool grants Dignify and
  Informant, both sanctions, which this mission doesn't allow (README §Mechanics by mission).
- **Healing and repair** (Alex, 2026-10-27): the [Sapper](../../factions/anarchical/units/an_bioLight_antiStructure.md)
  repairs. TODO: the Anarchists have no healer today. The Field Hospital was removed, and its
  heal is planned as a Collective upgrade, "Bio Heal", which isn't built, and this mission
  has no upgrades (README §Mechanics by mission).

## Reinforces

- From mission 1: counters, garrisoning, defection (cutting the enemy's Compounds), shooting
  aircraft, air transport through a gap in SAM coverage, the Watch Tower warning
- From mission 2: crushing, Sapper abilities, stagger (now while building under fire). Not
  ordnances: this mission has no sanctions (the earlier draft listed both).

## Player fantasy

The cell that held out becomes a war band able to take the fight to the Colonials.

## Narrative justification

Breaking the siege in mission 1 and holding out in mission 2 earn the Anarchists the space and
the following to rebuild. The target is a larger Colonial base than mission 1's, with more
Colonial technology to contend with (Alex, 2026-10-27). TODO: the story is to be reframed by
Alex once the mechanics each mission teaches are settled (README §Mechanics by mission).

## Setup

Numbers are illustration; the scene will hold the real values.

- **Commanders:**
  - **Player** — Anarchical.
  - **Enemy** — a Colonial bot, **scripted only**. Its counterattacks, defenders and garrisons
    are authored. It does not build or expand.
- **Starting base**, placed in the scene: a [Stronghold](../../factions/anarchical/structures/an_commandCenter.md) and [Irregulars](../../factions/anarchical/units/an_bioLight_builder.md) as builders.
- **Tech available, to Tier 1:**
  - [Safehouse](../../factions/anarchical/structures/an_infrastructure.md)
  - [Redoubt](../../factions/anarchical/structures/an_barracks.md)
  - [Chop Shop](../../factions/anarchical/structures/an_warFactory.md)
  - [Hangar](../../factions/anarchical/structures/an_airField.md)
  - [Stockpile](../../factions/anarchical/structures/an_tech1.md)

  TODO: a scenario cannot cap tech or exclude pieces yet (README §Impact of mission 1's build).
- **Map:**
  - Extraction sites near the base, and a lithium pond further out
  - The Colonial base split into distinct sections, each a problem for a different tool (below)
  - Drawn as a topology first and imported through the map generator's image mode
- **Enemies:** the Colonial base, its defending groups each sharing one defended area.
  - **Counterattacks** put pressure on the economy. Each is set off by a beat (a structure
    built, a tier reached, a section entered) or by the previous one being spent, never by a
    repeating timer, and never while the previous one lives. They come from the section that
    teaches the counter the player needs next (the first from the armour park).

## The enemy base, section by section

Each section is a different question, and each answer is something the player has to build. The pairings are a starting point for scenario authoring.

| Section | Problem | Tool that answers it |
| --- | --- | --- |
| Armour park | [Matildas](../../factions/colonial/units/cl_mechMedium_antiMech.md) and [Sloops](../../factions/colonial/units/cl_mechMedium_antiLight.md) | Anti-MECH: [Shock Troopers](../../factions/anarchical/units/an_bioMedium_antiMech.md) from the Redoubt, or [Kamikazes](../../factions/anarchical/units/an_aircraftLight_antiMech.md) from the Hangar |
| Kill zone | Open ground covered by [Watch Towers](../../factions/colonial/structures/cl_defense_antiLight.md), where infantry on foot are cut down | A ground transport: a [Collective](../../factions/anarchical/units/an_mechLight_transport.md) early, or a [War Wagon](../../factions/anarchical/units/an_mechStrong_transport.md) after the Stockpile |
| Plateau battery | [Bombards](../../factions/colonial/structures/cl_defense_antiStructure.md) on high ground with no ground route up. TODO — how the Bombards are used is deferred to a separate session | An air transport: the [Raven](../../factions/anarchical/units/an_aircraftLight_transport.md). Reinforces mission 1 |
| SAM screen | [SAM sites](../../factions/colonial/structures/cl_defense_antiAircraft.md) guarding the approach to the plateau | A ground force clears them before the Raven can fly in. Like mission 1's climax, which is fine (Alex, 2026-10-27) |
| Barracks quarter | Massed Colonial infantry in garrisoned buildings | [Sharpshooters](../../factions/anarchical/units/an_bioLight_antiBio.md) or a [Juggernaut](../../factions/anarchical/units/an_bioStrong_antiLight.md) after the Stockpile, and the [Toxin Tractor](../../factions/anarchical/units/an_mechMedium_antiBio.md) to clear garrisons |
| The Citadel | The [command centre](../../factions/colonial/structures/cl_commandCenter.md), with STRONG armour that resists everything | [Sappers](../../factions/anarchical/units/an_bioLight_antiStructure.md) delivered by transport |

## Objectives

One strict `ObjectiveChain` that reads the beats below.

1. **Expand the economy**, in sub-steps: build a Safehouse, then extractors.
2. **Build production and train an army**, in sub-steps: a Redoubt, then a squad rallied to a
   point.
3. **Reach Tier 1** (the Stockpile).
4. **Destroy the Colonial base**, section by section, ending with the Citadel (order: Q1).

Failure conditions (proposed, Q2): the Stronghold must survive, and the player must keep at
least one builder or the means to train one.

**What the player is shown.** Marked: the neutral buildings fit for a Safehouse, the
extraction sites, the lithium pond, each section's key pieces while its sub-step is current,
the Citadel. Reveals: each section's outline once objective 4 is shown, so the player can plan
which tool to build. None for a route through the kill zone.

**Autosaves** (proposed): when Tier 1 is reached, and after each section falls.

## Teaching beats

- **Introduce:**
  - Build a Safehouse in a neutral building and extractors on the nearby sites.
  - Then the Redoubt, and train infantry with a rally point set.
- **Develop:**
  - The first counterattack and the armour park push the player to train counters.
  - The lithium pond offers a faster income that runs out and is exposed.
  - The kill zone makes the Collective worth building.
- **Twist:** the plateau battery can't be reached on foot. The player needs the Hangar, the
  Raven, and a ground push to clear the SAMs first. It echoes mission 1's climax, now with a
  base the player built behind it (Alex, 2026-10-27: a similar climax is fine).
- **Conclude:** a combined assault on the barracks quarter and the Citadel, using whatever the player built for each section.

Help notes (proposed). "New" notes are to be written for the How to Play library.

| Introduced by | Notes, in order |
|---|---|
| Mission start | Building structures (new); Safehouses and infrastructure (new) |
| Safehouse built | Extractors (new) |
| Objective 1 done | Training and rally points (new) |
| Lithium pond first sighted | Lithium ponds (new) |
| Objective 2 done | The tech tree (new) |
| Your infrastructure falls short | Defection, from your side (new; mission 1 told it only through objective text) |
| Kill zone first sighted | Ground transports (new) |
| TODO: once there is a healer | Healing (new) |
| First structure damaged | Repair (new) |
| Barracks quarter first sighted | Clearing garrisons (new) |
| Stronghold's pool first charged | Shared ability pools (new) |
| Objective 3 done | Air transport (reused, shown again as a reminder) |
| Watch Tower first sighted | the Watch Tower warning (see mission 2's Q4) |

## Constraints

- Tech capped at Tier 1. The Clandestine Lab and its units (Condor, Hijacker) are excluded.
- The [MLRS](../../factions/anarchical/units/an_mechMedium_artillery.md) is excluded. It needs a spotter, and spotting isn't part of the prologue; it's planned for the [challenge series](../challenges/README.md).
- No sanctions. Missions are self-contained, so nothing from mission 2 carries over.
- No upgrades.
- No mechanic before it is explained, checked against every placed and spawned piece.

## Scenario file

TODO — link once it exists under `scenes/scenarios/prologue/`.

## Open questions

**Q1. Section order.** Strict order (as mission 1) or free order once objective 4 is shown?
*Why it matters:* free order is what an economy mission is about. But sub-steps can't express
it: reaching a later sub-step completes every earlier one
([objectives-and-completion](../../systems/scenario-scripting/objectives-and-completion.md)
§Sub-steps). Free order needs the sections as parallel objectives shown together, with the
Citadel chained after all of them.
*Leaning:* free order. This needs no new scripting: the section objectives sit outside the
`ObjectiveChain`, each with objective 3 as its prerequisite, and the Citadel's objective has
all of them as prerequisites.

**Q2. Failure conditions.** Lose the Stronghold, or lose every builder with no way to train
one?
*Leaning:* both.
