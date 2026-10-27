# Prologue Campaign Design

Status: draft. The prologue is three missions played as the **Anarchists** against the **Colonials**. Mission 1 teaches the mechanics every RTS player meets, mission 2 the mechanics specific to dissent-horizon, and mission 3 running an economy. Mechanics set the order, and each mission gets a story reason for its situation.

The prologue is kept small on purpose so new players aren't overwhelmed. Skills a player can pick up later — the control idioms, spatial counters and spotting, and requisition — live in the [challenge series](../challenges/README.md) instead.

## How these docs map to the repo

- A mission doc describes design intent: what it teaches, why the story puts the player there, and the beats.
- Each mission doc links to its scenario file under `scenes/scenarios/`, which holds the real placements, triggers and values. Numbers in a mission doc are illustration only, so they don't go stale when the scenario is retuned. Piece names link to their spec docs for the same reason.
- Every mission doc uses the same template: Status, Teaches, Reinforces, Player fantasy, Narrative justification, Setup, Objectives, Teaching beats, Constraints, Scenario file, Open questions. Since mission 1 was built, Setup names its commanders, Objectives lists the chain, its failure conditions, what is marked and revealed, and the autosaves, and Teaching beats has a help-note table. [Mission design](../mission-design.md) records why.

| # | Doc | Teaches | Story hook (draft) |
| --- | --- | --- | --- |
| 1 | [Pervasive mechanics](01-pervasive-mechanics.md) | Unit control, garrisoning, the counter system, defection, shooting aircraft, air transport | In the middle of a Colonial siege on allied Anarchists, a lone Warlord frees captives, takes Colonial Ravens, flies past the SAM screen, cripples the besiegers' base and destroys its Citadel |
| 2 | [Game-specific mechanics](02-game-specific-mechanics.md) | Unit abilities (via the Sapper), crushing, stealth, dominion generation, ordnances, garrison clearing | A defunct base with Distress Signals holds out while it banks dominion for Informant and Mortar Strike |
| 3 | [Macroeconomics](03-macroeconomics.md) | Structure and unit production, resource collection, the tech tree, ground transports | Destroy a Colonial base; each part of it calls for a different tool (story hook open, see its doc) |

## Narrative arc

The player's toolkit grows with the Anarchists' situation: a squad caught in someone else's battle, then a cell holding a ruined base, then a war band able to build and take the fight to the Colonials.

- **Mission 1 (in medias res):** no base and no economy, because the player arrives mid-battle with whatever survived.
- **Mission 2 (holding out):** the base is defunct, so there's no production. The Anarchists' leverage is dominion — their Warlords' following — not industry.
- **Mission 3 (taking initiative):** the first full base, used for a direct assault.

The arc should end on a hook into the main campaigns, not a full resolution.

## Impact of mission 1's build

Mission 1 grew while it was built (2026-10-18 to 10-26). Re-reading the campaign against it
(2026-10-27, [mission-design](../mission-design.md) §Re-check the campaign after every build):

- **Air transport and anti-air are mission 1's** (Alex, 2026-10-27). The player takes Ravens by
  destroying SAM sites, then finds a gap in the base's SAM coverage, and the *Shooting aircraft*
  and *Air transport* notes are shown there. Mission 3 reinforces air transport and teaches the
  ground transports. Its climax may resemble mission 1's, and that is fine (Alex, 2026-10-27).
- **Defection is taught in full in mission 1** (Compounds cut, SAM sites go dark). Mission 3 can
  lean on it.
- **Mission 1's story ends with the besiegers' Citadel destroyed.** Mission 3's target is
  instead a larger Colonial base with more Colonial technology to contend with (Alex,
  2026-10-27). Its narrative is to be reframed once the mechanics each mission teaches are
  settled (§Mechanics by mission).
- **Mission 1 already shows Colonial prisons:** Compounds holding the player's infantry, freed by
  setting off the hazards against them. Mission 2's Stock Truck captures can pay that off.
- **An MLRS appears in mission 1**, in the allied relief. The player never commands it, so it
  is not introduced to the player there and can be introduced later (Alex, 2026-10-27).
- **Engine gaps for missions 2 and 3:** a scenario cannot yet limit a commander's sanction grid
  or what it can build and train. `PlayerSlot` sets only starting energy and dominion. Mission 2
  needs "only Informant and Mortar Strike" and "no production". Mission 3 needs "Tier 1 at
  most, no Clandestine Lab, no MLRS". To be built; scoped on its own, apart from the challenges'
  input conditions, which belong to another system (Alex, 2026-10-27).
- **How to Play gained 14 notes** in four categories. Missions 2 and 3 reuse those and add
  their own. Each doc's help-note table lists the new ones.

## Mechanics by mission

Draft for review, 2026-10-27. Alex is settling the mechanics first and will reframe each
mission's narrative from them. *Taught* means a note or beat explains it and the player uses
it. *Shown* means it appears without being taught, and something later must teach it. Tiers
are from the [design framework](../../design-framework/README.md).

### The player's mechanics

| Mechanic | Tier | Taught | Reinforced | Notes |
|---|---|---|---|---|
| Selecting, moving, the camera, minimap, command card | Generic | 1 | all | built |
| Attacking, attack-move | Generic | 1 | all | built |
| Damage table (frame × armour × type) | Generic | 1 (*Damage types*) | 2, 3 | built |
| Garrisoning: cover, firing from it, leaving it | Generic | 1 | 2, 3 | built |
| Shooting aircraft; what hits air and what doesn't | Generic | 1 | 3 | built |
| Air transport | Generic | 1 | 3 | built |
| Defection, cutting the enemy's infrastructure | Generic | 1 | 3 | taught by objective text only; no note (M1) |
| Volatile pieces (chain explosions) | Shared | 1, untaught | 2 (Q2 prisons) | the *Attacking* note doesn't cover it (M1) |
| Crushing | Generic | 2 | 3 | |
| Unit abilities: arm, target, charge, cooldown (Sapper) | Generic | 2 | 3 | |
| Dominion: Retinue | Slot | 2 | — | none in 3, which has no sanctions |
| Sanctions and ordnances (Informant, Mortar Strike) | Generic | 2 | — | as above |
| Stealth and detection | Slot | 2 | 3? | the Watch Tower's detection |
| Garrison clearing (Toxin Tractor) | Slot | 2 | 3 | (M2) |
| Structure production, the Safehouse | Generic | 3 | — | |
| Infrastructure, from the player's side | Generic | 3 | — | proposed 2026-10-27 |
| Unit production, rally points | Generic | 3 | — | |
| Extractors and lithium ponds | Generic | 3 | — | |
| Tech tree and prerequisites | Generic | 3 | — | |
| Ground transports | Generic | 3 | — | |
| Stagger: a hit blocks building and healing | Generic | none | — | met constantly once the player builds under fire (M3) |
| Shared ability pools | Generic | none | — | (M4) |
| Veterancy, repair and healing | Generic | none | — | (M4) |
| MLRS and spotting | Shared | none (shown in 1, the ally's) | — | challenge C2 |
| Modifiers, selector keys, control groups | Generic | none | — | challenge C1 |
| Requisition | Generic | none | — | challenge C3 |
| Upgrades; Anarchist signatures (EMP, scavenging); the Hijacker; Dignify, Ambush, Scavenge | — | none | — | main campaign |

### The enemy's mechanics (what the player must read)

| Colonial mechanic | Met in | Notes |
|---|---|---|
| Watch Towers (hit ground only, detect) | 1 (the warning), 2 (detection) | |
| SAM sites (hit air only) | 1, 3 | |
| Compounds as infrastructure, and as prisons | 1 | prisons shown, capture not explained until 2 |
| Stock Truck capture | 2 | |
| Vehicles that crush (Sloop, Matilda) | 2, 3 | |
| "More Colonial technology" in mission 3 | 3 | which? (M5) |
| Bombard spotting, Freeze | none | the Colonial signatures; Bombards deferred to their own session |

### Questions to settle the list

- **M1. Mission 1's untaught mechanics.** Defection is taught only through objective text, and
  the volatile chain not at all. Add two library notes, *Infrastructure and defection* (raised
  with objective 8) and *Volatile pieces* (with objective 2)? *Leaning:* yes, both. Mission 3
  can reuse the first.
- **M2. Mission 2's load.** It teaches six mechanics (abilities, crushing, stealth, dominion,
  ordnances, garrison clearing) against mission 3's six, but they are newer and less familiar.
  Garrison clearing could move to mission 3, whose barracks quarter already needs the Toxin
  Tractor. *Leaning:* move it, keeping mission 2's twist as stealth routing past detection.
- **M3. Stagger.** It is generic and high-prevalence, and the first time a player sees a builder
  stop under fire is mission 3. Teach it there, with a note raised the first time a build is
  blocked? *Leaning:* yes.
- **M4. Generic mechanics with no home:** shared ability pools, veterancy, repair and healing.
  Main campaign, a challenge, or somewhere in the prologue? *Leaning:* main campaign, except
  shared pools if mission 2's Sappers draw on one.
- **M5. Mission 3's Colonial technology.** The base is larger, with more Colonial technology.
  Which? Candidates: Freeze (a Colonial signature, and a disable the player has not met), the
  Gunship or other Colonial sanctions cast against the player, Bombards (deferred), and
  higher-tier units. *Why it matters:* each one the player must read is a mechanic to teach,
  and mission 3 already teaches six.

## Deliberately left out

Kept out of the prologue to avoid overloading it. Each is either a challenge or main-campaign material.

| Mechanic | Where it goes |
| --- | --- |
| Modifier controls (Alt narrow, Ctrl broaden, Shift append), the F1–F3 selector matrix, control groups | [Challenge series](../challenges/README.md) |
| Spatial counters (outpacing projectiles, kiting, turrets), spotting. Spotting-dependent pieces, like the MLRS, are kept out of the player's hands in the prologue (mission 1's allied relief carries MLRS the player never commands) | [Challenge series](../challenges/README.md) |
| Requisition | [Challenge series](../challenges/README.md) |
| Command centre drop and the free extractor drops | Main campaign or skirmish onboarding; the prologue starts players with a base |
| Anarchist signature mechanics (disable/EMP, scavenging), the Hijacker, Dignify, Ambush, Scavenge | Main campaign |
| Shelters, static defence design, upgrades, aerial rearm, alliances, superweapons | Main campaign |

## Decisions

- **Missions are self-contained.** There is no metaprogression: no units, veterancy or sanctions carry over between missions. The story continues across them, but each mission's setup stands alone.
- **No mechanic appears before it's explained.** Each mission's design is constrained so it can't. For example, mission 1 has no enemy ground vehicles, so there's no crushing and there are no wrecks to scavenge.
- **Every mission uses scripted objectives**, not HEGEMONY, so each lesson is presented to the player.
- **Bombard use is deferred.** TODO — how the Colonial Bombards behave in missions 1 and 3 is being worked out in a separate session.

## Open questions

None.
