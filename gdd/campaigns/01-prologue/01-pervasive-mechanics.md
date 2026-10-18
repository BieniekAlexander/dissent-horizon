# Mission 1 — Pervasive mechanics

Status: draft. The player arrives mid-battle with a small Anarchist force, grows it by rescuing pinned-down allies, and strikes the besieging Colonials' base. No base, no economy.

## Teaches

- **Unit control:** selecting, box-selecting, move, attack, attack-move, stop
- **Garrisoning:** entering and leaving a neutral building, and the protection and range a garrison gives
- **The counter system:** Frame (BIO vs MECH) × Armour (Light, Medium, Strong) against damage types, including a matchup where one unit can barely hurt another

## Reinforces

Nothing; this is the first mission.

## Player fantasy

Thrown into someone else's losing battle, a small squad turns it around by picking the right fights.

## Narrative justification

The Colonials are besieging an allied Anarchist position. The player's force is caught inside the siege when the mission opens, so there's no base and no setup. Allied cells are pinned down across the battlefield, and freeing them is how the force grows. The siege is sustained by the Colonials' base on the edge of the battle, and the critical blow against it ends the siege.

## Setup

- **Starting force:** a few [Irregulars](../../factions/anarchical/units/an_bioLight_builder.md). They are cheap, generalist BIO infantry, which makes them a good baseline to compare specialists against.
- **Collected on the way:** each pinned-down cell adds one unit type, chosen so its counter role is obvious:
  - [Shock Troopers](../../factions/anarchical/units/an_bioMedium_antiMech.md) against Colonial vehicles
  - [Sharpshooters](../../factions/anarchical/units/an_bioLight_antiBio.md) against Colonial infantry
  - [Sappers](../../factions/anarchical/units/an_bioLight_antiStructure.md) for the strike on the base
- **Map:** a ruined town. Neutral buildings line the route, open ground between them is exposed, and the Colonial base sits at the far edge.
- **Enemies:** the besieging Colonial army.
  - BIO: [Recruits](../../factions/colonial/units/cl_bioLight_antiLight.md) and [Badgers](../../factions/colonial/units/cl_bioLight_antiMech.md)
  - MECH: [Matildas](../../factions/colonial/units/cl_mechMedium_antiMech.md)
  - The base: [Bombards](../../factions/colonial/structures/cl_defense_antiStructure.md) shelling the allied position, which suits the Colonials' siege theme

## Objectives

1. Break out of the opening position (unit control).
2. Free the pinned-down cells (counters, each with the unit that solves it).
3. Cross the exposed ground to reach the Colonial base (garrisoning).
4. Destroy the Bombards (the critical blow).

## Teaching beats

- **Introduce:** move and attack with Irregulars against a small Recruit group. Then attack-move, as a second group arrives from the fog.
- **Develop:** one counter at a time.
  - A Matilda pins the first cell. Irregulars barely scratch it, and the freed Shock Troopers kill it. This is the deliberately lopsided matchup.
  - The next cell is pinned by Colonial infantry, and the freed Sharpshooters win there.
  - Then mixed groups that need the player to send the right units at the right targets.
- **Twist:** crossing open ground under fire. Garrisoning a building lets the force survive and outrange the enemy, and leaving it at the right moment lets the force advance.
- **Conclude:** the Sappers join, and the force fights to the Bombards and destroys them.

## Constraints

- No base, production, sanctions or ordnances.
- Enemy vehicles should not drive through player infantry. Crushing is game-wide but is taught in mission 2.
- Keep counter matchups readable: one enemy type per encounter until the mixed beat.

## Scenario file

TODO — link once it exists under `scenes/scenarios/`.

## Open questions

- Does losing every unit fail the mission, or restart from the last freed cell?
- How much of the damage table does the UI show (readouts, cursor hints), versus letting players learn from the results?
- Destroyed Matildas leave wrecks that Anarchist infantry can scavenge. Scavenging isn't taught in the prologue, so suppress it here, or let it happen unexplained?
- Do the Bombards need spotters to fire at the player? If so, spotting appears here before the challenge that teaches it.
