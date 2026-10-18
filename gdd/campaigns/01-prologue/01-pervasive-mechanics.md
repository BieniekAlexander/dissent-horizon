# Mission 1 — Pervasive mechanics

Status: draft. The player arrives mid-battle with a small Anarchist force, grows it by rescuing pinned-down allies, and strikes the besieging Colonials' base. No base, no economy.

## Teaches

- **Unit control:** selecting, box-selecting, move, attack, attack-move, stop
- **Garrisoning:** entering and leaving a neutral building, and the protection and range a garrison gives
- **The counter system:** Frame (BIO vs MECH) × Armour (Light, Medium, Strong) against damage types, including a matchup where one unit can barely hurt another
- **Defection:** destroying the structures that supply a commander's infrastructure puts it in **defection**, and its structures become **defective**, so defences lose their weapons and abilities. Units are unaffected. That's how a small force breaks into a defended base. Rules: [production-and-economy](../../systems/macroeconomics/production-and-economy.md) §Defection.

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
- **Map:** a ruined town. Neutral buildings line the route, open ground between them is exposed, and the Colonial base sits at the far edge.
- **Enemies:** the besieging Colonial army.
  - BIO: [Recruits](../../factions/colonial/units/cl_bioLight_antiLight.md) and [Badgers](../../factions/colonial/units/cl_bioLight_antiMech.md)
  - MECH: [Matildas](../../factions/colonial/units/cl_mechMedium_antiMech.md)
  - The base: [Bombards](../../factions/colonial/structures/cl_defense_antiStructure.md) shelling the allied position, which suits the Colonials' siege theme, and [Watch Towers](../../factions/colonial/structures/cl_defense_antiLight.md) defending it
  - The base's power: [Compounds](../../factions/colonial/structures/cl_infrastructure.md), the Colonial infrastructure providers, sitting outside the defended perimeter. Their supply is all that keeps the defences and Bombards working.

## Objectives

1. Break out of the opening position (unit control).
2. Free the pinned-down cells (counters, each with the unit that solves it).
3. Cross the exposed ground to reach the Colonial base (garrisoning).
4. Destroy the Compounds to cut the base's power (infrastructure).
5. Break into the darkened base and destroy the Bombards (the critical blow).

## Teaching beats

- **Introduce:** move and attack with Irregulars against a small Recruit group. Then attack-move, as a second group arrives from the fog.
- **Develop:** one counter at a time.
  - A Matilda pins the first cell. Irregulars barely scratch it, and the freed Shock Troopers kill it. This is the deliberately lopsided matchup.
  - The next cell is pinned by Colonial infantry, and the freed Sharpshooters win there.
  - Then mixed groups that need the player to send the right units at the right targets.
- **Twist:** crossing open ground under fire. Garrisoning a building lets the force survive and outrange the enemy, and leaving it at the right moment lets the force advance.
- **Conclude:**
  - The base's defences are too strong to assault head-on.
  - The force destroys the Compounds outside the perimeter instead. The Colonials fall into defection, and the defences and Bombards become defective: the defective badge appears over each, and they stop firing.
  - The force walks in and destroys the Bombards, using the counters it has learned against the Colonial units still defending. Those units are unaffected by the power loss.

## Constraints

- No base, production, sanctions, ordnances or unit abilities. The Sapper is left out for this reason: its only way to damage anything is its Plant ability, which mission 2 teaches.
- Enemy vehicles should not drive through player infantry. Crushing is game-wide but is taught in mission 2.
- Keep counter matchups readable: one enemy type per encounter until the mixed beat.

## Scenario file

TODO — link once it exists under `scenes/scenarios/`.

## Open questions

- Does losing every unit fail the mission, or restart from the last freed cell?
- How much of the damage table does the UI show (readouts, cursor hints), versus letting players learn from the results?
- Destroyed Matildas leave wrecks that Anarchist infantry can scavenge. Scavenging isn't taught in the prologue, so suppress it here, or let it happen unexplained?
- Spotting isn't part of the prologue, but Bombards fire through spotters and beacons. Should the Bombards' shelling be scripted (at the allied position, never at the player), or should they not fire at all here?
