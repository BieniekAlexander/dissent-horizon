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
  (expanded 2026-10-18). The hills are about 3 high: a steep face, then a flat top nothing can
  reach. Neutral buildings: none for now.
  1. **Start:** the player's clearing, southwest of the ally's start. It does not open onto the main
     corridor.
  2. **West corridor:** north from the start, about 22 wide. Partway up, the **rescue**: when the
     player walks into a trigger, 9 of the ally's Irregulars appear ahead of them and 5 enemy Recruits
     further north, and the two attack each other. An invisible Scout reveals the fight, since the
     ally does not share vision. The trigger is placed so the player arrives just out of the fight's
     reach (first probe: 16.5 from the nearest Recruit against the Warlord's reach of 12, so no shots
     yet; TODO — move the Recruits' spawn about 3 south if a shot or two is wanted). When the
     Recruits are dead the Irregulars push north onto a second trigger, which ends the fight's
     reveal, sends 2 Clippers at them and reveals where they strike.
  3. **The prisons:** at its north end, two enemy
     [Compounds](../../factions/colonial/structures/cl_infrastructure.md), each holding 3 of the
     player's Irregulars with its prison switched off (`OccupantDominionGenerator.is_disabled`), so
     they serve no sentence. [Power cells](../../factions/neutral/tokens/nt_powerCell.md) and
     [battery racks](../../factions/neutral/structures/nt_batteryRack.md) stand against each
     Compound, close enough that blowing them up destroys it; a destroyed Compound hands its
     prisoners back to the player.
  4. **The first skirmish:** east of the prisons, northwest of the ally's start, 3 Recruits defending
     a clearing (the game's Defend order).
  5. **Down into the main corridor:** a passage south from the skirmish joins the main corridor just
     east of the ally's Safehouses.
  6. **Main corridor:** west–east, about 80 cells long and 18 wide; the ally holds the west end and
     the enemy the east.
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
