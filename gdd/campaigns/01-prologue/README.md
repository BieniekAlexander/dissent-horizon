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
| 2 | [Game-specific mechanics](02-game-specific-mechanics.md) | Unit abilities (via the Sapper), capture and crushing, stealth, repair and stagger, dominion generation, the sanction system | Sappers lost and freed, an allied base relieved and taken over, then a race against the Colonials for dominion (narrative to be reframed) |
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
| Defection, cutting the enemy's infrastructure | Generic | 1 | 3 | taught by the defective badge, now shown to everyone |
| Volatile pieces (chain explosions) | Shared | 1 | 2 (Q2 prisons) | the hazards are marked as objective 2 targets (TODO: scene) |
| Capture (Stock Truck) and crushing | Generic | 2 | 3 | a Stock Truck's capture is its crush; the note follows the Sappers' capture |
| Unit abilities: arm, target, charge, cooldown (Sapper) | Generic | 2, phase 1 | 3 | |
| Dominion: needs your faction's command centre; Retinue, and the Colonial route | Slot | 2, phase 5 | 3 (required) | the command-centre rule is a game-wide change (Alex, 2026-10-27) |
| The sanction system | Generic | 2, phase 5 | 3 | |
| Stealth and detection; BIO units see stealth close up | Slot | 2, phase 2 | 3? | |
| Garrison clearing (Toxin Tractor) | Slot | 3 | — | moved from 2 |
| Structure production, the Safehouse | Generic | 3 | — | |
| Infrastructure, from the player's side | Generic | 3 | — | proposed 2026-10-27 |
| Unit production, rally points | Generic | 3 | — | |
| Extractors and lithium ponds | Generic | 3 | — | |
| Tech tree and prerequisites | Generic | 3 | — | |
| Ground transports | Generic | 3 | — | |
| Stagger: a hit stops a repair, a build, a Plant or a heal | Generic | 2, with repair | 3 | |
| Shared ability pools | Generic | 3, the Stronghold (Dignify, Informant) | — | mission 2 now has two shared pools; move the note there? (mission 2 Q1) |
| Repair (Sapper; Irregulars never repair) | Generic | 2, phase 4 | 3 | |
| Healing | Generic | none | — | Anarchist healing deferred |
| Veterancy | Generic | none | — | deferred |
| MLRS and spotting | Shared | none (shown in 1, the ally's) | — | challenge C2 |
| Modifiers, selector keys, control groups | Generic | none | — | challenge C1 |
| Requisition | Generic | none | — | challenge C3 |
| Individual sanctions and abilities beyond those used to teach a system | — | tooltips | — | not taught one by one: the sanction system is taught in 2, and the player reads the tooltips for any later ordnance or ability (Alex, 2026-10-27) |
| Anarchist signatures (EMP, scavenging); the Hijacker | — | none | — | main campaign |

### The enemy's mechanics (what the player must read)

| Colonial mechanic | Met in | Notes |
|---|---|---|
| Watch Towers (hit ground only, detect) | 1 (the warning), 2 (phase 1's boundary) | |
| SAM sites (hit air only) | 1, 2, 3 | |
| Compounds as infrastructure, and as prisons | 1, 2 | |
| Stock Truck capture | 2, phase 1 | |
| Vehicles that crush (Matilda; the Sloop in 3) | 2, phase 4; 3 | |
| "More Colonial technology" in mission 3 | 3 | not scoped yet (Alex, 2026-10-27) |
| Colonial dominion and the Drop sanction | 2, phase 5 | the enemy buys Drop 1–3 by a mission script |
| Bombard spotting, Freeze | none | the Colonial signatures; Bombards deferred to their own session |

### Decided (Alex, 2026-10-27)

- Mission 1 marks the prison hazards as objective 2 targets, beside the Compounds. Defection is
  taught by its visual indicator, with no note.
- Garrison clearing moves from mission 2 to mission 3.
- Stagger is taught in mission 2 (with repair, since the 2026-10-27 redesign). The note also
  covers building, Plant and healing.
- Shared ability pools are taught in mission 3, through the player's Stronghold. Repair moved
  to mission 2 with its redesign. Veterancy is deferred.
- Mission 3's extra Colonial technology is not scoped yet.

### Resolved (Alex, 2026-10-27)

- The defective badge is shown to everyone, so the player sees the enemy's defences go dark.
  It used to show only to the defective commander's side, a rule an agent session added on
  2026-10-04 (commit 9fe29674); `StatusVisuals._shows_defective` and
  [condition-visuals](../../systems/ux/ui/condition-visuals.md) are changed.
- Mission 3 has sanctions and requires dominion generation, so the Stronghold's pool (Dignify,
  Informant) is there to teach. Its "no sanctions" and "no upgrades" constraints are dropped,
  and upgrades are no longer kept out of the prologue.
- Anarchist healing is deferred.
- Individual ordnances and abilities aren't taught one by one. The sanction system is taught in
  mission 2, and later ones are learned from their tooltips. Mission 3 offers every sanction.
- Mission 2 has no upgrades because the player can't afford the structures that research them.

## Deliberately left out

Kept out of the prologue to avoid overloading it. Each is either a challenge or main-campaign material.

| Mechanic | Where it goes |
| --- | --- |
| Modifier controls (Alt narrow, Ctrl broaden, Shift append), the F1–F3 selector matrix, control groups | [Challenge series](../challenges/README.md) |
| Spatial counters (outpacing projectiles, kiting, turrets), spotting. Spotting-dependent pieces, like the MLRS, are kept out of the player's hands in the prologue (mission 1's allied relief carries MLRS the player never commands) | [Challenge series](../challenges/README.md) |
| Requisition | [Challenge series](../challenges/README.md) |
| Command centre drop and the free extractor drops | Main campaign or skirmish onboarding; the prologue starts players with a base |
| Anarchist signature mechanics (disable/EMP, scavenging), the Hijacker | Main campaign |
| Shelters, static defence design, aerial rearm, alliances, superweapons | Main campaign |

## Decisions

- **Missions are self-contained.** There is no metaprogression: no units, veterancy or sanctions carry over between missions. The story continues across them, but each mission's setup stands alone.
- **No mechanic appears before it's explained.** Each mission's design is constrained so it can't. For example, mission 1 has no enemy ground vehicles, so there's no crushing and there are no wrecks to scavenge.
- **Every mission uses scripted objectives**, not HEGEMONY, so each lesson is presented to the player.
- **Bombard use is deferred.** TODO — how the Colonial Bombards behave in missions 1 and 3 is being worked out in a separate session.

## Open questions

None.
