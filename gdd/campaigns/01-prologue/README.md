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

- **Air transport and anti-air are now mission 1's.** The player takes Ravens by destroying SAM
  sites, then finds a gap in the base's SAM coverage, and the *Shooting aircraft* and *Air
  transport* notes are shown there. Mission 3 now reinforces air transport and teaches only the
  ground transports, and its SAM-screen-then-Raven twist repeats mission 1's climax (open
  question in [mission 3](03-macroeconomics.md)).
- **Defection is taught in full in mission 1** (Compounds cut, SAM sites go dark). Mission 3 can
  lean on it.
- **Mission 1's story ends with the besiegers' Citadel destroyed.** Mission 3's hook, "the
  Colonial base that sustained the siege is now the target", no longer holds (open question in
  mission 3).
- **Mission 1 already shows Colonial prisons:** Compounds holding the player's infantry, freed by
  setting off the hazards against them. Mission 2's Stock Truck captures can pay that off.
- **An MLRS appears in mission 1**, carried in by the allied relief, although the prologue
  leaves out spotting-dependent pieces (below). Open question in
  [mission 1](01-pervasive-mechanics.md).
- **Engine gaps for missions 2 and 3:** a scenario cannot yet limit a commander's sanction grid
  or what it can build and train. `PlayerSlot` sets only starting energy and dominion. Mission 2
  needs "only Informant and Mortar Strike" and "no production". Mission 3 needs "Tier 1 at
  most, no Clandestine Lab, no MLRS".
- **How to Play gained 14 notes** in four categories. Missions 2 and 3 reuse those and add
  their own. Each doc's help-note table lists the new ones.

## Deliberately left out

Kept out of the prologue to avoid overloading it. Each is either a challenge or main-campaign material.

| Mechanic | Where it goes |
| --- | --- |
| Modifier controls (Alt narrow, Ctrl broaden, Shift append), the F1–F3 selector matrix, control groups | [Challenge series](../challenges/README.md) |
| Spatial counters (outpacing projectiles, kiting, turrets), spotting. Spotting-dependent pieces, like the MLRS, are kept out of the prologue (TODO: mission 1's allied relief carries MLRS; see its open questions) | [Challenge series](../challenges/README.md) |
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
