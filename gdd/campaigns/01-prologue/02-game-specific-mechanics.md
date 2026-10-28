# Mission 2 — Game-specific mechanics

Status: draft, not built. Redesigned by Alex on 2026-10-27, superseding the defunct-base draft.
The player starts with three Sappers deep in a Colonial base, loses them to Stock Trucks, sneaks
a stealthed squad past patrols to bring in reinforcements, frees the Sappers, flies to save an
allied base, takes it over, and then races the Colonials for dominion.
[mission-design](../mission-design.md) applies throughout.

## Teaches

- **Unit abilities**, through the [Sapper](../../factions/anarchical/units/an_bioLight_antiStructure.md):
  [Plant](../../factions/anarchical/abilities/plant.md) and [Detonate](../../factions/anarchical/abilities/detonate.md),
  with the charge and cooldown they show.
- **Capture and crushing:** Stock Trucks run the Sappers over and capture them. A Stock Truck
  is the one crusher that captures what it crushes instead of killing it (Alex, 2026-10-27),
  so this is the crushing lesson. The crushing note comes once all three are taken.
- **Stealth and detection:** stealth hides a unit until it attacks, and stealth from Informant
  comes back once it stops. BIO units, and dedicated detectors, see a stealthed unit inside a
  smaller vision radius. So the player hits and runs.
- **Repair:** Sappers repair the allied Stronghold. **Stagger** is taught with it: a hit stops a
  repair, as it stops a build, a Plant or a heal.
- **Dominion generation:** a faction's dominion generation needs its command centre (the rule
  under §Rules this mission depends on), then the Anarchist route (Retinue) and the Colonial
  route (capture into Compounds), side by side.
- **The sanction system:** buying a sanction with dominion and casting it, once the player can
  afford one. Individual ordnances are left to their tooltips.

## Reinforces

From mission 1: unit control, counters, garrisoning, volatile hazards (the SAM sites' explosives),
air transport (the Ravens), freeing captives from a Compound.

## Player fantasy

A cell that loses its saboteurs, gets them back, saves an allied base and turns it against the
Colonials.

## Narrative justification

TODO — Alex to reframe the narrative once the mechanics are settled.

## Setup

Numbers are illustration; the scene will hold the real values.

- **Commanders:**
  - **Player** — Anarchical.
  - **Ally** — Anarchical, holding one base, which passes to the player after the repair
    (phase 4). Scripted only.
  - **Enemy** — Colonial, with a base. Details to come (Alex). Scripted, except in phase 5: its
    Stock Trucks are bot-driven, gathering dominion by capture (Alex, 2026-10-27, pending
    playtesting), and it buys the Drop sanction through a mission script (§Engine work).
- **The allied base:** a [Stronghold](../../factions/anarchical/structures/an_commandCenter.md),
  two [Distress Signals](../../factions/anarchical/structures/an_support2.md) and 5
  [Safehouses](../../factions/anarchical/structures/an_infrastructure.md) (5 for now).
- **Shelters:** 3. One is easy for the player to defend, and two are contested, which is where
  the dominion race is fought. The player can also destroy Compounds to cut the enemy's
  dominion generation.
- **Mission restrictions** (the scenario-level restriction feature, scoped separately):
  - the player's Stronghold can't train units;
  - Irregulars can't build (in mission 1 too);
  - the player's sanctions are only Informant, Mortar Strike, Ambush and Dignify. The
    Stronghold's third ordnance is still to be designed; whether it is offered here depends on
    that design (Alex, 2026-10-27).

## Phases and beats

### Phase 1: Sappers (Plant)

- The player starts with 3 Sappers in a section of the enemy base where no enemy unit
  threatens them. [Watch Towers](../../factions/colonial/structures/cl_defense_antiLight.md) and
  posted [Recruits](../../factions/colonial/units/cl_bioLight_antiLight.md) keep them from
  roaming beyond it.
- Objective: destroy two [Barracks](../../factions/colonial/structures/cl_barracks.md) and a
  [Sky Port](../../factions/colonial/structures/cl_airField.md) with planted charges.
- When they're down, [Stock Trucks](../../factions/colonial/units/cl_mechLight_dominionGen.md)
  drive in, capture the Sappers and deliver them to a Compound, where they are freed in
  phase 3.
- **Loss exception.** Losing every unit to capture is an elimination (`MISSION`'s implicit
  wipe-out loss doesn't count captives:
  [objectives-and-completion](../../systems/scenario-scripting/objectives-and-completion.md)
  §The MISSION loss is implicit). Phase 1 needs an exception (§Engine work).
- Once the Sappers are delivered, the 3 stealthed Irregulars spawn for phase 2.

### Phase 2: Stealth

- At the start of the phase, a note explains stealth (§Teaches).
- The player has 3 [Irregulars](../../factions/anarchical/units/an_bioLight_builder.md) under
  [Informant](../../factions/anarchical/sanctions/informant.md)'s stealth.
- 2 patrols of 3 Recruits each move through the area.
- Objective: destroy 3 [SAM sites](../../factions/colonial/structures/cl_defense_antiAircraft.md),
  spread apart, by setting off the explosives beside each one.
- Then 2 [Ravens](../../factions/anarchical/units/an_aircraftLight_transport.md) fly in, each
  dropping 4 Irregulars and 1 [Warlord](../../factions/anarchical/units/an_bioMedium_dominionGen.md),
  near the player. The Ravens are the player's from then on (Alex, 2026-10-27).

### Phase 3: Rescue

- Objective: destroy the Compound holding the Sappers, directly (no hazards). Destroying it
  frees them.
- No objective for the patrols. They defend the Compound because they're near it, so the
  player fights them on the way.

### Phase 4: Relief and repair

- Objective: bring the army, with the Sappers, to the allied base, which Recruits and
  [Matildas](../../factions/colonial/units/cl_mechMedium_antiMech.md) are attacking. They target
  the Stronghold, slowly enough that the player has ample time to fly there.
- Failure: the Stronghold is destroyed.
- Once the attackers are dead, the repair note (with stagger) is raised, and an objective:
  repair the Stronghold. When it's repaired, the base passes to the player.

### Phase 5: The dominion race

- Notes: the command-centre rule, then Anarchist and Colonial dominion generation.
- Objectives:
  - **Destroy the enemy's Supply Beacons** (n/3). The
    [Supply Beacon](../../factions/colonial/structures/cl_support2.md) casts the Drop sanction.
  - **Don't let the enemy gather 1,000 dominion** (the number is to be revisited). It counts
    everything the enemy has gathered, not what it holds, and the label shows the running
    total (§Engine work).
- The enemy gathers dominion and attacks the player. Some of its waves come from the
  [Drop](../../factions/colonial/sanctions/drop.md) sanction, which it buys as its dominion
  allows.
- When the player has enough dominion for the cheapest of its four sanctions, the sanction
  note is raised.

## Objectives

Phases 1–4 run as one strict `ObjectiveChain`. The two phase-5 objectives are shown together.

1. Destroy the Barracks and the Sky Port (2 + 1).
2. Destroy the SAM sites (n/3).
3. Free the Sappers.
4. Relieve the allied base.
5. Repair the Stronghold.
6. Destroy the Supply Beacons (n/3).
7. FAILURE: the enemy gathers 1,000 dominion.

Failures: the Stronghold destroyed in phase 4; the dominion total in phase 5; and the implicit
wipe-out loss, except during phase 1.

## Help notes

| Raised by | Notes |
|---|---|
| Mission start | Abilities (new: Plant, Detonate, charge, cooldown) |
| The Sappers all captured | Crushing (new) |
| Phase 2 start | Stealth and detection (new) |
| The attackers at the allied base dead | Repair (new); Stagger (new) |
| The base passes to the player | Dominion and the command centre (new); Anarchist dominion (new); Colonial dominion (new) |
| The player can afford a sanction | Sanctions (new) |

## Rules this mission depends on

- **Dominion needs a command centre of the generating piece's faction** (Alex, 2026-10-27). A
  Warlord generates dominion only while its commander owns an Anarchical command centre. A
  commander that owns pieces of another faction needs that faction's command centre for them.
  Game-wide, not mission-specific. TODO: scope it as a system change; refactoring mission 1
  for it is deferred.
- **The Distress Signal casts Mortar Strike and Ambush from one pool** (120 s), and the
  Hideout is removed (Alex, 2026-10-27). So the player meets two shared pools here: the
  Stronghold's (Dignify, Informant) and the Distress Signal's.
- **Irregulars can't repair, game-wide** (Alex, 2026-10-27; `repairs: false` in their spec).

## Engine work

- **Scenario restrictions:** training at a structure, building by a unit type, and the
  sanction grid offered. Scoped separately; mission 1 needs it too (Irregulars can't build).
- **A rule-based sanction unlock script** for a scripted enemy: the Colonials buy only Drop 1,
  2 and 3, which the grid's rule (2 unlocks in a tier to open the next) forbids. Authored per
  mission, and likely reusable.
- **A phase-1 exception to the wipe-out loss**, while the Sappers are captives.
- **An objective label that shows a live count** (the enemy's dominion gathered). TODO: check
  whether objective labels support this today.
- **The dominion command-centre rule** (§Rules).

## Constraints

- No production: the Stronghold can't train, and Irregulars can't build.
- No upgrades: the player can't afford the structures that research them.
- No mechanic before it is explained, checked against every placed and spawned piece. The
  Matildas at the allied base come after the crushing note.

## Scenario file

TODO — link once it exists under `scenes/scenarios/prologue/`.

## Open questions

Resolved 2026-10-27 (Alex):

- **Crushing:** a Stock Truck's capture is its crush, so the Sappers' capture teaches it.
- **The Ravens** are the player's after they drop their load. The army is exactly 16, the seats
  of two Ravens.
- **Enemy dominion:** the Stock Trucks are bot-driven for now, pending playtesting.
- **Ambush's prerequisite:** irrelevant here, since the mission hands the player its casters.

**Q1. Shared pools.** Mission 2 now gives the player two shared pools (the Stronghold's and the
Distress Signal's). Move the shared-pool note here from mission 3?

**Q2. Ambush in skirmish.** Its caster, the Distress Signal, needs the Stockpile, while the
Hideout needed only a Barracks, so Ambush arrives later in a skirmish match. Fine?
