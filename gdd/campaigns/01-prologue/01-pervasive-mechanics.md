# Mission 1 — Pervasive mechanics

Status: draft, first scene built for iteration. The player arrives mid-battle in a lane where allied and Colonial waves are already fighting, and strikes the besieging Colonials' base. No base, no economy.

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

Decided 2026-10-18 (Alex), superseding the first draft's starting force, ruined-town map and
pinned-down cells. Numbers here are illustration; the scene holds the real values.

- **Commanders:**
  - **Player** — Anarchical, alliance 1.
  - **Ally** — an Anarchical bot on the player's alliance. It does **not** share vision with the
    player: its slot turns off `PlayerSlot.shares_vision_with_allies`
    ([target-acquisition](../../systems/combat/target-acquisition.md) §Alliances), so its pieces show only
    inside the player's own vision. Allies share vision by default; this mission is the edge case.
  - **Enemy** — a Colonial bot on its own alliance.
  - Both bots are **scripted only**: everything they do is the scripting below. Their slots switch
    off every brain job that acts (`PlayerSlot.disabled_bot_jobs`), keeping only perception. PASSIVE
    alone is not enough: a passive brain still defends its base.
- **Starting force:** one [Warlord](../../factions/anarchical/units/an_bioMedium_dominionGen.md),
  in a clearing southwest of the ally's start.
- **Map:** flat regions joined into one route, with hills too steep to cross everywhere else
  (expanded 2026-10-18, and again the same day for the reordered beats). The hills are about 3
  high: a steep face, then a flat top nothing can reach. The beats come in this order, and the
  ally's squad — the Irregulars of the rescue — leads the player through the first four:
  1. **Start:** the player's clearing, southwest of everything. It does not open onto the main
     corridor.
  2. **The rescue**, in the west corridor north of the start (about 22 wide): when the player walks
     into a trigger, 9 of the ally's Irregulars appear ahead of them and 5 enemy Recruits further
     north, and the two attack each other. An invisible reveal shows the fight, since the ally does
     not share vision, and goes dark once the Recruits are dead. The trigger is meant to leave the
     player just out of the fight's reach; the last probe had the player arrive about 27 from the
     nearest Recruit, against the Warlord's reach of 12 (TODO — tune).
  3. **The prisons**, at the corridor's north end: the squad walks there and waits, clear of the
     hazards. Two enemy [Compounds](../../factions/colonial/structures/cl_infrastructure.md) each
     hold 3 of the player's Irregulars with the prison switched off
     (`OccupantDominionGenerator.is_disabled`), so they serve no sentence.
     [Power cells](../../factions/neutral/tokens/nt_powerCell.md) and
     [battery racks](../../factions/neutral/structures/nt_batteryRack.md) stand against each
     Compound as one chain: shooting any of them sets off all of them, and the blasts destroy the
     Compound, which hands its prisoners back to the player. A right-click on a volatile piece is an
     attack ([the-click-ladder](../../systems/commands/the-click-ladder.md), rung 9).
  4. **The outpost**, a short walk east: the player's first fight, 3 Recruits defending a clearing
     (the game's Defend order). The squad stays out of it: it moves on only once both prisons are
     down AND the outpost is cleared.
  5. **The garrison**, further east along a road: the squad waits beside a neutral building. When
     the player puts a unit inside it, the squad walks on east, about 26 past the building, and
     there 2 Clippers fall on it — spawned 12 beyond the squad, as seen from the building, and 8
     apart (`EventSpawnEntities.follow_group`). That keeps them out of the garrisoned Warlord's
     reach until the squad is dead (Alex, 2026-10-18); then they turn on the building and the
     Warlord shoots them down. A reveal shows the player the squad's end. The player evacuates and
     walks on. Leaving the building is not losing a base (`Garrison.is_borrowed`).
  6. **The fork**, past the building: walking into it reveals all of it. East is open ground with 4
     [Watch Towers](../../factions/colonial/structures/cl_defense_antiLight.md) and 2 Compounds
     behind them that power them — plainly approachable, worth coming back for — and an empty lane
     running on east past them (nothing placed there yet). South, a narrow passage drops into the
     main corridor between the two sides' bases, on the ally's side. Walking down it autosaves
     ([saved-games](../../systems/commands/saved-games.md) §Autosaves).
  7. **Main corridor:** west–east, about 80 long and 18 wide; the ally holds the west end and the
     enemy the east.
  8. **The south lane** (added 2026-10-18): a second west–east lane south of the main corridor,
     about 100 long and 16 wide, joined to the main corridor's west end. West to east:
     - two more prison Compounds, each holding a Warlord and 3 Irregulars of the player's (their
       garrisons raised from 3 to 4 to fit), with the chain of hazards on their WEST side, the
       side the player comes from: wrapped round the corner each grid-aligned Compound shows to
       the west;
     - a guard post: 4 Recruits and 2 Clippers on Defend;
     - three neutral buildings together; beyond them 12 Recruits in three groups of 4, who
       attack-move west down the lane the moment a player's unit enters the buildings' region;
     - at the lane's end, 3 [SAM sites](../../factions/colonial/structures/cl_defense_antiAircraft.md)
       with 2 Compounds among them, each holding 2 of the player's Irregulars (no hazards: the
       player brings them down by force). When all three SAM sites are down, 3
       [Ravens](../../factions/anarchical/units/an_aircraftLight_transport.md) of the player's
       fly in from off the map, beyond the lane's end, and land about 5 from the player's unit
       nearest the SAM field (Alex, 2026-10-18; they were the ally's, parked there and handed
       over, before).
  9. **The push on the base** (added 2026-10-18). The goal of this phase: the player loads the
     army into the Ravens, which carry 8 BIO units each, finds a gap in the enemy's air defences,
     and destroys enough of the base's Compounds to make its defences defective.
     - **The mesa outposts.** The hill country east of the west corridor has a flat top no ground
       unit can reach. Three small enemy outposts stand on it, reachable only by air. Each has 2
       SAM sites and a group of 3 neutral buildings, and one of: a Barracks, 2 empty Compounds,
       or a Sky Port.
     - **The main corridor's enemy end** gains 2 SAM sites.
     - **The main base**, east of the old map edge, which the ends of all three west–east
       corridors open onto. It has:
       - a Citadel in the centre, 3 Barracks and 2 Sky Ports spread through it;
       - 3 groups of neutral buildings;
       - 10 SAM sites and 24 empty Compounds.

       The two southern corridors are covered by SAM sites. The top one, past the Watch
       Towers' field, has none, and no base SAM site reaches the base's northern third: that is
       the gap to fly in by.
     - **Infrastructure**, one enemy pool (Alex, 2026-10-18). The base's Compound count is sized
       so that, with the four prisons and the two lane-end Compounds already destroyed (the route
       here), the enemy goes defective once 14 of the 24 are lost (58%). Its SAM sites then stop
       firing. The layout builder prints this ledger whenever it runs.
     - TODO: no dialogs, objectives, or win condition for the phase yet.
- **Statics:**
  - Ally (west): [Safehouses](../../factions/anarchical/structures/an_infrastructure.md), each
    garrisoned with [Irregulars](../../factions/anarchical/units/an_bioLight_builder.md) from the
    start.
  - Enemy (east): [Watch Towers](../../factions/colonial/structures/cl_defense_antiLight.md), with
    [Compounds](../../factions/colonial/structures/cl_infrastructure.md) behind them supplying
    their infrastructure. Without the Compounds the enemy would start in defection; they are also
    what the later cut-the-power beat destroys.
- **Waves:** on a repeating timer, each side spawns a wave near its start and sends it down the
  lane at the other side, where it keeps re-engaging (a `ScenarioTactic` per wave).
  - Ally waves: 3 Irregulars and 2 Warlords.
  - Enemy waves: 3 [Recruits](../../factions/colonial/units/cl_bioLight_antiLight.md) and 2
    [Clippers](../../factions/colonial/units/cl_aircraftLight_antiLight.md). The Clipper is in the
    retired Petrel's place; the Warlord, which hits air, is its counter.
  - A wave's order is one group order, so it moves at its slowest member's speed and the Clippers
    keep pace with the Recruits ([ai/squads-and-relations](../../systems/ai/squads-and-relations.md)).
- **Ending:** losing every unit fails the mission. There is no win condition yet. TODO — the
  objectives below predate this setup and are to be reconciled with it.
- **Bombards:** none placed yet. TODO — how the Bombards are used is deferred to a separate session.

## Objectives

TODO — from the first draft, not yet reconciled with the 2026-10-18 setup above.

1. Break out of the opening position (unit control).
2. Free the pinned-down cells (counters, each with the unit that solves it).
3. Cross the exposed ground to reach the Colonial base (garrisoning).
4. Destroy the Compounds to cut the base's power (infrastructure).
5. Break into the darkened base and destroy the Bombards (the critical blow).

## Teaching beats

TODO — from the first draft, not yet reconciled with the 2026-10-18 setup above.

- **Introduce:** move and attack with Irregulars against a small Recruit group. Then attack-move, as a second group arrives from the fog.
- **Develop:** one counter at a time.
  - A Watch Tower pins the first cell. Irregulars barely scratch its MECH frame, and the freed Shock Troopers take it down. This is the deliberately lopsided matchup, and it shows that structures have a frame and armour like units do.
  - The next cell is pinned by Colonial infantry, and the freed Sharpshooters win there.
  - Then mixed groups that need the player to send the right units at the right targets.
- **Twist:** crossing open ground under fire. Garrisoning a building lets the force survive and outrange the enemy, and leaving it at the right moment lets the force advance.
- **Conclude:**
  - The base's defences are too strong to assault head-on.
  - The force destroys the Compounds outside the perimeter instead. The Colonials fall into defection, and the defences and Bombards become defective: the defective badge appears over each, and they stop firing.
  - The force walks in and destroys the Bombards, using the counters it has learned against the Colonial units still defending. Those units are unaffected by the power loss.

## Constraints

- No base, production, sanctions, ordnances or unit abilities. The Sapper is left out for this reason: its only way to damage anything is its Plant ability, which mission 2 teaches.
- No enemy ground vehicles. That rules out crushing and wrecks (scavenging) before the missions that explain them.
- Losing every unit fails the mission.
- TODO — how damage relationships are communicated to the player is undecided.
- Keep counter matchups readable: one enemy type per encounter until the mixed beat.

## Scenario file

[`scenes/scenarios/prologue/m1_pervasive_mechanics.tscn`](../../../scenes/scenarios/prologue/m1_pervasive_mechanics.tscn).
Its terrain is generated by `tools/missions/prologue_m1_terrain.gd` (the terrain's primary);
the scene itself was laid down once by `tools/missions/prologue_m1_layout.gd` and is now the
primary, edited in the editor.

## Open questions

None.
