# Mission 1 — Pervasive mechanics

Status: draft, first scene built for iteration. The player arrives mid-battle in a lane where allied and Colonial waves are already fighting, and strikes the besieging Colonials' base. No base, no economy.

## Teaches

- **Unit control:** selecting, box-selecting, move, attack, attack-move. The stop order is not taught (Alex, 2026-10-26).
- **The camera, the minimap and the command card**
- **Garrisoning:** entering and leaving a neutral building, and the protection and range a garrison gives
- **The counter system:** Frame (BIO vs MECH) × Armour (Light, Medium, Strong) against damage types, including a matchup where one unit can barely hurt another
- **Shooting aircraft and anti-air:** the Warlord hits air; Watch Towers hit only the ground, SAM sites only aircraft.
- **Air transport:** loading the Ravens and flying them through a gap in the SAM coverage.
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
    player at first: its slot turns off `PlayerSlot.shares_vision_with_allies`
    ([target-acquisition](../../systems/combat/target-acquisition.md) §Alliances), so its pieces show only
    inside the player's own vision. It starts sharing once the Clippers are down (`EventShareVision`
    under ClippersDown; Alex, 2026-10-26).
  - **Enemy** — a Colonial bot on its own alliance.
  - Both bots are **scripted only**: everything they do is the scripting below. Their slots switch
    off every brain job that acts (`PlayerSlot.disabled_bot_jobs`), keeping only perception. PASSIVE
    alone is not enough: a passive brain still defends its base.
- **Starting force:** one [Warlord](../../factions/anarchical/units/an_bioMedium_dominionGen.md),
  in the map's south-west corner, beside the sea.
- **Map:** imported from Alex's drawing with the Map Generator's image mode
  ([map-from-image](../../systems/terrain-and-navigation/map-from-image.md)), replacing the
  grey-boxed map of mesas. About 156 × 116: five levels, a river across the north with one
  wadeable ford, a lake in the west, and a sea beside the start. The drawing was a one-shot seed:
  the scene is primary from here. Every piece and trigger of the grey-boxed mission was moved onto
  it, beat by beat, following the sketch it was drawn from
  (`gdd/campaigns/01-prologue/m1_topology_sketch.png`), on 2026-10-23. On 2026-10-26 the map was
  shrunk (Alex): the start's corner — the sea and its shallows — kept as drawn, everything else
  0.56 along each axis, and every piece and trigger moved through the same mapping. Alex then
  tweaked the scaled drawing, which replaced the original as
  `resources/maps/prologue_mission_1_draft_drawing.ora`, and was imported again the same day — and
  again after a later edit that turned part of the west lake into a wadeable crossing, every
  piece kept where Alex had placed it. TODO — these positions are a first pass
  for Alex to refine. The beats come in this order, and the ally's squad — the Irregulars of the
  rescue — leads the player through the first four:
  1. **Start:** the south-west corner, beside the sea.
  2. **The rescue**, at the rendezvous east of the start, past the shallows (a circle of radius 5,
     halved by Alex 2026-10-26): 9 of the ally's Irregulars stand ahead of it and 5 enemy Recruits
     further north, both placed in the scene and holding fire at their posts (Alex, 2026-10-26;
     they used to spawn). When the player reaches the rendezvous (the last waypoint of objective 1), the two attack each other. An invisible reveal shows the fight, since the ally does
     not share vision, and goes dark once the Recruits are dead. The trigger is meant to leave the
     player just out of the fight's reach; the last probe had the player arrive about 27 from the
     nearest Recruit, against the Warlord's reach of 12 (TODO — tune).
  3. **The prisons**, on the plateau south-east of the start's shallows (Alex, 2026-10-26): the
     squad walks there and waits on the plateau's north side, clear of the hazards, holding fire
     so it leaves the Compounds to the player (Alex, 2026-10-26). East of the
     plateau, two [Watch Towers](../../factions/colonial/structures/cl_defense_antiLight.md)
     line the top of the ramp onto the next level-3 ground, at the plateau's own height (Alex,
     2026-10-26). Two enemy [Compounds](../../factions/colonial/structures/cl_infrastructure.md),
     side by side with a chain of explosives between them (Alex, 2026-10-26), each
     holds 3 of the player's Irregulars with the prison switched off
     (`OccupantDominionGenerator.is_disabled`), so they serve no sentence. A second prison like
     it stands on the western plateau with its own chain, and a third, holding two of the
     player's Warlords, on the plateau north-east of the allied base with its chain against its
     south corner; both are optional — neither the objective nor the squad waits on them (Alex,
     2026-10-26). TODO — after the 2026-10-26 drawing edit the western prison's two battery racks
     stand on slope or water; Alex to move them.
     [Power cells](../../factions/neutral/tokens/nt_powerCell.md) and
     [battery racks](../../factions/neutral/structures/nt_batteryRack.md) stand against each
     prison as one chain: shooting any of them sets off all of them, and the blasts destroy the
     Compound, which hands its prisoners back to the player. A right-click on a volatile piece is an
     attack ([the-click-ladder](../../systems/commands/the-click-ladder.md), rung 9).
  4. **The outpost**, back north-west, at the western plateau's east end: the player's first fight, 3 Recruits defending a clearing
     (the game's Defend order). Once the plateau's prisons are down the squad leads the player
     toward it, stopping about 14 short (Alex, 2026-10-26), and stays out of the fight: it moves on
     only once the outpost is cleared too.
  5. **The garrison**, beside the outpost: the squad waits beside a neutral building,
     `NtBuildingLarge3` (Alex, 2026-10-26). When the player puts a unit inside it, the squad walks
     on toward the Watch Tower field, about 17 past the building, and
     there 2 Clippers fall on it, flying in from the enemy's field plateau to the north, where they
     spawn 8 apart (Alex, 2026-10-26; they used to appear beside the squad). They kill the squad,
     then turn on the building and the garrisoned Warlord shoots them down. A reveal shows the player the squad's end. The player evacuates and
     walks on. Leaving the building is not losing a base (`Garrison.is_borrowed`).
  6. **The fork**, past the building: walking into it reveals the base entrance ahead, 4
     [Watch Towers](../../factions/colonial/structures/cl_defense_antiLight.md) on the central
     plateau's south-west slope, with 2 Compounds behind them that power them — plainly
     approachable, worth coming back for.
  7. **The lane:** from the ally's base in the north-west to the Citadel in the east, across the
     central lowland. The enemy's end is held by 3 Watch Towers, 2 Compounds and 2 SAM sites.
  8. **The northern route** (the south lane of the grey-boxed map, 2026-10-18), from the central
     plateau north to the river and over its ford:
     - two more prison Compounds on the central plateau's top, each holding a Warlord and 3
       Irregulars of the player's (their garrisons raised from 3 to 4 to fit), with the chain of
       hazards on their WEST side, wrapped round the corner each grid-aligned Compound shows to
       the west;
     - three neutral buildings together south of the ford, whose region calls 6 Recruits to
       charge west the moment a player's unit enters it; until then those 6 guard the new
       crossing in the west lake on a Defend order (Alex, 2026-10-26; there were 12, waiting
       beyond the buildings);
     - past the ford, a guard post: 4 Recruits and 2 Clippers on Defend;
     - the outpost, the crossing and the guard post each defend a shared area (a `DefendedArea`
       cylinder under the order), so the whole group answers anything inside it rather than
       each unit only its own aggro range, which let the player pick them off one by one
       (Alex, 2026-10-26);
     - beyond it, 3 [SAM sites](../../factions/colonial/structures/cl_defense_antiAircraft.md)
       with a Compound among them holding 2 of the player's Irregulars, with a short hazard chain
       against it (Alex, 2026-10-26; there were two Compounds, unchained). Beside them, 3
       [Ravens](../../factions/anarchical/units/an_aircraftLight_transport.md) stand landed,
       owned by no commander (Alex, 2026-10-26; they were the ally's); when all three SAM sites
       are down they become the player's (Alex, 2026-10-21, reverting the 2026-10-18 fly-in).
  9. **The push on the base** (added 2026-10-18). The goal of this phase: the player loads the
     army into the Ravens, which carry 8 BIO units each, finds a gap in the enemy's air defences,
     and destroys enough of the base's Compounds to make its defences defective.
     - **The outposts.** Three small enemy outposts, scattered (Alex, 2026-10-23; on the
       grey-boxed map they shared a mesa): on the ridge south of the river, south of the central
       plateau, and east where the river ends. Each has 2 SAM sites and a group of 3 neutral
       buildings, and one of: a Barracks, 2 empty Compounds, or a Sky Port.
     - **The main base**, in the east. It has:
       - the Citadel, 4 Barracks and 3 Sky Ports (Alex, 2026-10-26);
       - groups of neutral buildings;
       - 6 SAM sites and 16 empty Compounds (Alex, 2026-10-26; were 12).

       The SAM sites leave one gap: an uncovered pocket just east of the Citadel, reached from
       the south. Objective 7's region sits in it, so reaching it tells the player they are in,
       and the next objective's markers lead on into the base (Alex, 2026-10-26).
     - **Infrastructure**, one enemy pool (Alex, 2026-10-18). The base's Compounds are sized so
       the enemy goes defective once about 30% of them are lost (2026-10-19), counting the
       prisons and lane-end Compound on the route here as already destroyed. Its SAM sites then
       stop firing. The ledger: 2700 provided against 2000 required at the start, counting the
       Citadel's own and the commander's base capacity. TODO — after Alex's 2026-10-26 edits
       the base goes defective once 4 of its 16 Compounds are lost (25%), or 3 if the player
       also destroyed the optional west prison; whether that is close enough to 30% is Alex's
       call.
     - **The allied relief** (Alex, 2026-10-21). The moment the enemy goes defective, 6 of the
       ally's Ravens fly in from the map's top-left corner (Alex, 2026-10-26): 3 carrying
       an [MLRS](../../factions/anarchical/units/an_mechMedium_artillery.md) and 4 Irregulars
       each, 3 carrying 2 Warlords and 4 Irregulars each. They land in the lane west of the
       Citadel, unload, and fly back off the map past that corner. The infantry attack-move to a point in front of the
       Citadel and Defend it; the MLRS attack the Citadel straight from where they land (Alex,
       2026-10-26). The MLRS is the ally's, so the player sees it but never commands it, and it
       stays unintroduced for the player (Alex, 2026-10-27). The MLRS
       rides a BIO-only Raven because a scenario's starting load is placement, not an order,
       and ignores the masks.
     - Defection also ends the enemy's lane waves, so the relief walks through (Alex,
       2026-10-21: the first build ground it down, each cleared wave provoking the next). The
       both-spent fallback stops with them, so the ally's waves stop too unless enemy units
       come near its spawn.
     - TODO: no dialogs for the phase yet.
- **Statics:**
  - Ally (north-west): [Safehouses](../../factions/anarchical/structures/an_infrastructure.md), each
    garrisoned with [Irregulars](../../factions/anarchical/units/an_bioLight_builder.md) from the
    start, and two Anarchist command centres.
  - Enemy (the lane's east end): [Watch Towers](../../factions/colonial/structures/cl_defense_antiLight.md), with
    [Compounds](../../factions/colonial/structures/cl_infrastructure.md) behind them supplying
    their infrastructure. Without the Compounds the enemy would start in defection; they are also
    what the later cut-the-power beat destroys.
- **Waves:** each side spawns a wave near its start and sends it down the lane at the other
  side, where it keeps re-engaging (a `ScenarioTactic` per wave). A side's next wave comes when
  the other side's units get within reach of its spawn point (an approach region round it), and
  never while any of its previous wave lives; when both waves are spent, both sides spawn
  (Alex, 2026-10-21, replacing a repeating timer). The aim is a stable front: neither side should
  reach the other's structures. Each approach region reaches half way down the lane, so the two
  meet in the middle (Alex, 2026-10-21). TODO — tune: in the first probe, with regions a little
  smaller, the ally lost about two waves to the enemy's one.
  - Ally waves: 3 Irregulars and 2 Warlords.
  - Enemy waves: 3 [Recruits](../../factions/colonial/units/cl_bioLight_antiLight.md) and 2
    [Clippers](../../factions/colonial/units/cl_aircraftLight_antiLight.md). The Clipper is in the
    retired Petrel's place; the Warlord, which hits air, is its counter.
  - A wave's order is one group order, so it moves at its slowest member's speed and the Clippers
    keep pace with the Recruits ([ai/squads-and-relations](../../systems/ai/squads-and-relations.md)).
- **Ending:** destroying the Citadel, the last objective, wins; losing every unit fails the
  mission.
- **Bombards:** none placed yet. TODO — how the Bombards are used is deferred to a separate session.

## Objectives

Decided 2026-10-21 (Alex), superseding the first draft's list. All nine are primary and
strictly in sequence (an `ObjectiveChain`): each is shown once the one before it is done, and
the last completing wins the mission. Each reads a beat of the Setup rather than driving one,
so a beat the player finishes early ticks its objective off the moment it is shown.

1. **Navigate to the nearby allied encampment:** walked as three waypoints, its sub-steps (Alex,
   2026-10-26; [objectives-and-completion](../../systems/scenario-scripting/objectives-and-completion.md)
   §Sub-steps), each a `Region` under `Waypoint1`–`Waypoint3`; the third is the rendezvous.
   RevealFirstWaypoint opens waypoint 1 at the start and each waypoint opens the next. The rescue
   fight (`RescueAmbush`) starts when this objective completes, so the rendezvous is authored in
   one place, `Waypoint3/Region` (Alex, 2026-10-26). Each waypoint is where its help note goes.
2. **Free the captives from the nearby Compounds:** the plateau's two prisons destroyed (group
   `prologue_m1_north_prisons`; the optional west prison is not in it).
3. **Take out the nearby squad:** the outpost's Recruits dead.
4. **Take cover in a nearby building:** every one of the player's units in the building on the
   road (Alex, 2026-10-26: one used to be enough). By design the player has no more units than it
   holds at that point.
5. **Destroy the aircraft:** the Clippers that strike the ally's squad dead, once they have
   struck.
6. **Find a way to get into the enemy camp:** the lane-end SAM sites destroyed. The Ravens
   are the player's from that moment, so the player sees them from that moment too; no
   separate sight check is needed. Walked as two sub-steps (Alex, 2026-10-26): entering a large
   region by the SAM sites (`SamFieldEntered/Region`) reveals the
   SAM sites and Ravens and adds a second checklist line, **Destroy the SAM sites to procure the
   air transports** (`DestroySamSites`), which carries the SAM sites' markers and completes with
   this objective.
7. **Find a flight path into the enemy base:** any of the player's units in the gap in the
   base's SAM coverage, east of the Citadel (Alex, 2026-10-26: it used to need a Raven).
8. **Destroy enough Compounds to cripple the camp's infrastructure:** the enemy in defection.
9. **Destroy the enemy Citadel**, which ends the mission.

Beside the chain, from the moment objective 2 is done: **At least one Warlord must survive**
(`WarlordsSurvive`, a `FAILURE`), lost when the player has no Warlord left. A Warlord sheltering
in a building or riding a transport is alive (`ConditionUnitCount.should_count_carried`).

**Autosaves** (Alex, 2026-10-26), these three and no others: when objective 2 is done (the first
Compounds down), when the Clippers are down (`ClippersDown`), and when **Destroy the SAM sites**
is revealed (`SamFieldEntered`). They replace one on the way down to the lane.

**What the player is shown** (Alex, 2026-10-26). The current objective's targets are marked in
the world and on the minimap, behind the fog
([highlights-and-fog-reveal](../../systems/scenario-scripting/highlights-and-fog-reveal.md)
§Marks are gated by the fog): the rendezvous region; the plateau prisons; the outpost's
Recruits; the garrison building; the Clippers; the lane-end SAM sites; the base's Compounds
(group `prologue_m1_base_compounds`); the Citadel. Objective 7, the gap in the SAM coverage, is
deliberately unmarked: finding it is the objective. Reveals:

- waypoint 1 is in sight from the start, each waypoint until it is reached, and the rendezvous
  from waypoint 2 until objective 1 is done;
- the plateau prisons are in sight from the moment objective 2 is shown until it is done;
- the outpost's squad is in sight from the moment objective 3 is shown until it is done;
- once the Clippers are down, the lane is revealed for good: one box, `LaneRegion` under the
  `ClippersDown` trigger, from the allied Safehouses to the enemy's lane-end towers and about
  the lane's width (Alex, 2026-10-26, replacing six circles raised near the allied base).

No other objective has a reveal (Alex, 2026-10-26: the mission is fine as configured).

## Teaching beats

Help notes (Alex, 2026-10-26). Each is a note of the
game-wide tutorial library (How to Play), except the one mission note, raised by an
`EventShowDialog` with `is_tutorial_note` under the trigger named, so it shows when that trigger
completes and teaches what the NEXT objective needs (killing the outpost squad brings the note on
garrisoning, because taking cover comes next), and is highlighted in the pause menu's How to Play
from then on. A skipped step's notes still show, since completing a step for the player runs its
events.

| Introduced by | Next objective | Notes, in order |
|---|---|---|
| `RevealFirstWaypoint` (mission start) | 1, waypoint 1, on-screen from the start | How to Play; Selecting and moving |
| `Waypoint1` reached | 1, waypoint 2 | The camera; The minimap; The command card |
| `Waypoint2` reached | 1, the rendezvous fight | none: the rendezvous has nothing to teach (Alex, 2026-10-26) |
| `Objective1Encampment` (rendezvous reached) | 2, free the captives | Attacking |
| `Objective2Captives` (plateau prisons down; the freed Irregulars join) | 3, take out the nearby squad | Selecting a group |
| `RampReached`: a unit on the ramp up to the outpost squad, once objective 2 is done | 3, take out the nearby squad | Attack-move; Damage types |
| `Objective3Squad` (outpost squad dead) | 4, take cover | Taking cover |
| `Objective4Cover` (player garrisoned) | 5, destroy the aircraft | Firing from cover |
| `Objective5Aircraft` (Clippers dead) | 6, find a way into the camp | Leaving cover; Shooting aircraft |
| `Objective6WayIn` (SAM sites down, Ravens handed over) | 7, find a flight path | Air transport |
| `WatchTowerSighted`: a Watch Tower first visible to the player | — | the mission's own note, `scenes/dialogs/prologue_m1/m1_watch_towers.tscn`: avoid Watch Towers until you have heavier armour; Watch Towers shoot only at the ground, SAM sites only at aircraft |

Objectives 8 and 9 (defection, the Citadel) get no notes, and the stop order is not taught
(Alex, 2026-10-26).

- `WatchTowerSighted` is `ConditionGroupVisible` over the group `prologue_m1_watch_towers`, true
  while any tower is visible to the player by the test that decides whether a commander sees a
  piece, so the ally's sight counts once it is shared and a remembered silhouette does not
  (Alex, 2026-10-26).
- `RampReached/Region` is a box on the slope where the lowland climbs to the squad's ground.
- Waypoint 1 must be inside the opening camera view; it is today, and has to stay so when moved.

## Constraints

- No base, production, sanctions, ordnances or unit abilities. The Sapper is left out for this reason: its only way to damage anything is its Plant ability, which mission 2 teaches.
- No enemy ground vehicles. That rules out crushing and wrecks (scavenging) before the missions that explain them.
- Losing every unit fails the mission.
- Damage relationships are told by the *Damage types* note, at the ramp to the outpost. TODO: whether anything in play shows them (a readout or a cue) is undecided.

## Map rework

The grey-boxed map was replaced on 2026-10-23 by one imported from Alex's drawing, and shrunk on 2026-10-26 (§Setup).
TODO — refine the piece and trigger positions with Alex, and fill the walks between beats;
see gdd/tasks.md T-126, and T-125 for the notes view its warnings feed.

## Scenario file

[`scenes/scenarios/prologue/m1_pervasive_mechanics.tscn`](../../../scenes/scenarios/prologue/m1_pervasive_mechanics.tscn).
Its terrain, `m1_pervasive_mechanics_map_terrain.tres` beside it, was imported once from the
drawing and is now primary; so is the scene, edited in the editor. Everything present from the first frame is placed in the scene,
so its position is authored directly; only what arrives during play is spawned by a trigger.

## Open questions

None.
