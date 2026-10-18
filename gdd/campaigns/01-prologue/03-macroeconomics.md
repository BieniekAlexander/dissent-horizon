# Mission 3 — Macroeconomics

Status: draft. A straightforward assault: build a base and an army, and destroy the Colonial base. Each part of the enemy base calls for a different tool, which is what motivates producing structures, climbing the tech tree and using transports.

## Teaches

- **Structure production:** builders, placement, build times, and the Safehouse. Anarchist infrastructure comes from occupying neutral buildings, not from a power plant.
- **Unit production:** training from production structures, and rally points.
- **Resource collection:** extractors on extraction sites, which are slow and never deplete, versus lithium ponds, which pay fast and run out.
- **The tech tree:** prerequisites, and that a higher tier unlocks the units for parts of the base the starting roster can't crack.
- **Transports:** carrying infantry past ground they can't cross or survive on foot.

## Reinforces

- Counters and garrisoning from mission 1
- Crushing, garrison clearing and ordnances from mission 2

## Player fantasy

The cell that held out becomes a war band able to take the fight to the Colonials.

## Narrative justification

Breaking the siege in mission 1 and holding out in mission 2 earns the Anarchists the space and the following to rebuild. The Colonial base that sustained the siege is now the target, and destroying it ends the prologue.

## Setup

- **Starting base:** a [Stronghold](../../factions/anarchical/structures/an_commandCenter.md) and [Irregulars](../../factions/anarchical/units/an_bioLight_builder.md) as builders.
- **Tech available, to Tier 1:**
  - [Safehouse](../../factions/anarchical/structures/an_infrastructure.md)
  - [Redoubt](../../factions/anarchical/structures/an_barracks.md)
  - [Chop Shop](../../factions/anarchical/structures/an_warFactory.md)
  - [Hangar](../../factions/anarchical/structures/an_airField.md)
  - [Stockpile](../../factions/anarchical/structures/an_tech1.md)
- **Map:**
  - Extraction sites near the base, and a lithium pond further out
  - The Colonial base split into distinct sections, each a problem for a different tool (below)
- **Enemies:** the Colonial base, with defenders and periodic counterattacks to give the economy pressure.

## The enemy base, section by section

Each section is a different question, and each answer is something the player has to build. The pairings are a starting point for scenario authoring.

| Section | Problem | Tool that answers it |
| --- | --- | --- |
| Armour park | [Matildas](../../factions/colonial/units/cl_mechMedium_antiMech.md) and [Sloops](../../factions/colonial/units/cl_mechMedium_antiLight.md) | Anti-MECH: [Shock Troopers](../../factions/anarchical/units/an_bioMedium_antiMech.md) from the Redoubt, or [Kamikazes](../../factions/anarchical/units/an_aircraftLight_antiMech.md) from the Hangar |
| Kill zone | Open ground covered by [Watch Towers](../../factions/colonial/structures/cl_defense_antiLight.md), where infantry on foot are cut down | A ground transport: a [Collective](../../factions/anarchical/units/an_mechLight_transport.md) early, or a [War Wagon](../../factions/anarchical/units/an_mechStrong_transport.md) after the Stockpile |
| Plateau battery | [Bombards](../../factions/colonial/structures/cl_defense_antiStructure.md) on high ground with no ground route up. TODO — how the Bombards are used is deferred to a separate session | An air transport: the [Raven](../../factions/anarchical/units/an_aircraftLight_transport.md) |
| SAM screen | [SAM sites](../../factions/colonial/structures/cl_defense_antiAircraft.md) guarding the approach to the plateau | A ground force has to clear them before the Raven can fly in, which sequences the assault |
| Barracks quarter | Massed Colonial infantry in garrisoned buildings | [Sharpshooters](../../factions/anarchical/units/an_bioLight_antiBio.md) or a [Juggernaut](../../factions/anarchical/units/an_bioStrong_antiLight.md) after the Stockpile, and the [Toxin Tractor](../../factions/anarchical/units/an_mechMedium_antiBio.md) to clear garrisons |
| The Citadel | The [command centre](../../factions/colonial/structures/cl_commandCenter.md), with STRONG armour that resists everything | [Sappers](../../factions/anarchical/units/an_bioLight_antiStructure.md) delivered by transport |

## Objectives

1. Expand the economy: build a Safehouse and extractors.
2. Build production and train an army.
3. Reach Tier 1 (the Stockpile).
4. Destroy the Colonial base.

## Teaching beats

- **Introduce:**
  - Build a Safehouse in a neutral building and extractors on the nearby sites.
  - Then the Redoubt, and train infantry with a rally point set.
- **Develop:**
  - The first counterattack and the armour park push the player to train counters.
  - The lithium pond offers a faster income that runs out and is exposed.
  - The kill zone makes the Collective worth building.
- **Twist:** the plateau battery can't be reached on foot. The player needs the Hangar, the Raven, and a ground push to clear the SAMs first.
- **Conclude:** a combined assault on the barracks quarter and the Citadel, using whatever the player built for each section.

## Constraints

- Tech capped at Tier 1. The Clandestine Lab and its units (Condor, Hijacker) are excluded.
- The [MLRS](../../factions/anarchical/units/an_mechMedium_artillery.md) is excluded. It needs a spotter, and spotting isn't part of the prologue; it's planned for the [challenge series](../challenges/README.md).
- No sanctions. Missions are self-contained, so nothing from mission 2 carries over.
- No upgrades.

## Scenario file

TODO — link once it exists under `scenes/scenarios/`.

## Open questions

None.
